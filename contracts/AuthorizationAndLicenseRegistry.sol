// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IUserRegistry {
    function isActiveUser(address userAddress) external view returns (bool);
    function getUserGroup(address userAddress) external view returns (uint8);
}

interface IPlatformEntitlementRegistry {
    function isActionAllowed(
        uint8 group,
        uint8 assetType,
        uint256 actionMask
    ) external view returns (bool);

    function getEntitlement(
        uint8 group,
        uint8 assetType
    )
        external
        view
        returns (
            uint256 actionMask,
            uint32 version,
            bool active,
            uint64 createdAt,
            uint64 updatedAt
        );
}

interface IAssetPolicyRegistry {
    function assetExists(bytes32 assetId) external view returns (bool);
    function policyExists(bytes32 assetId) external view returns (bool);
    function isAssetPolicyActive(bytes32 assetId) external view returns (bool);

    function isActionPermitted(
        bytes32 assetId,
        uint8 group,
        uint256 actionMask
    ) external view returns (bool);

    function getAsset(
        bytes32 assetId
    )
        external
        view
        returns (
            uint8 assetType,
            address owner,
            bytes32 metadataHash,
            string memory metadataURI,
            bool active,
            uint64 registeredAt,
            uint64 updatedAt
        );

    function getPolicy(
        bytes32 assetId
    )
        external
        view
        returns (
            bytes32 policyHash,
            string memory policyURI,
            uint64 validFrom,
            uint64 validUntil,
            uint32 version,
            bool active,
            uint64 createdAt,
            uint64 updatedAt
        );
}

contract AuthorizationAndLicenseRegistry {
    enum DenialReason {
        None,
        UserInactiveOrMissing,
        AssetMissing,
        PolicyMissingOrInactive,
        InvalidAction,
        PlatformEntitlementDenied,
        AssetPolicyDenied,
        RequestAlreadyProcessed
    }

    struct License {
        bytes32 licenseId;
        bytes32 requestId;
        address user;
        address assetOwner;
        address issuedBy;
        bytes32 assetId;
        uint8 assetType;
        uint8 userGroup;
        uint256 actionMask;
        bytes32 assetPolicyHash;
        uint32 assetPolicyVersion;
        uint32 entitlementVersion;
        uint64 issuedAt;
        uint64 validUntil;
        bool exists;
    }

    struct AuthorizationContext {
        uint8 userGroup;
        uint8 assetType;
        address assetOwner;
        bytes32 assetPolicyHash;
        uint32 assetPolicyVersion;
        uint32 entitlementVersion;
        uint64 policyValidUntil;
    }

    address public platformAdmin;

    IUserRegistry public userRegistry;
    IPlatformEntitlementRegistry public entitlementRegistry;
    IAssetPolicyRegistry public assetPolicyRegistry;

    mapping(address => bool) public authorizedOrchestrators;
    mapping(bytes32 => License) private licenses;
    mapping(bytes32 => bytes32) private requestToLicense;

    uint256 public totalLicenses;

    event OrchestratorStatusUpdated(
        address indexed orchestrator,
        bool authorized,
        uint256 timestamp
    );

    event LicenseIssued(
        bytes32 indexed licenseId,
        bytes32 indexed requestId,
        address indexed user,
        bytes32 assetId,
        uint8 assetType,
        uint8 userGroup,
        uint256 actionMask,
        bytes32 assetPolicyHash,
        uint32 assetPolicyVersion,
        uint32 entitlementVersion,
        uint64 issuedAt,
        uint64 validUntil
    );

    event PlatformAdminTransferred(
        address indexed previousAdmin,
        address indexed newAdmin
    );

    error NotPlatformAdmin();
    error NotAuthorizedOrchestrator();
    error InvalidAddress();
    error InvalidRequestId();
    error InvalidAssetId();
    error InvalidAction();
    error UserInactiveOrMissing();
    error AssetMissing();
    error PolicyMissingOrInactive();
    error PlatformEntitlementDenied();
    error AssetPolicyDenied();
    error RequestAlreadyProcessed();
    error LicenseNotFound();
    error SameStatus();

    modifier onlyPlatformAdmin() {
        if (msg.sender != platformAdmin) {
            revert NotPlatformAdmin();
        }
        _;
    }

    modifier onlyAuthorizedOrchestrator() {
        if (!authorizedOrchestrators[msg.sender]) {
            revert NotAuthorizedOrchestrator();
        }
        _;
    }

    constructor(
        address userRegistryAddress,
        address entitlementRegistryAddress,
        address assetPolicyRegistryAddress
    ) {
        if (
            userRegistryAddress == address(0) ||
            entitlementRegistryAddress == address(0) ||
            assetPolicyRegistryAddress == address(0)
        ) {
            revert InvalidAddress();
        }

        platformAdmin = msg.sender;
        userRegistry = IUserRegistry(userRegistryAddress);
        entitlementRegistry = IPlatformEntitlementRegistry(
            entitlementRegistryAddress
        );
        assetPolicyRegistry = IAssetPolicyRegistry(
            assetPolicyRegistryAddress
        );

        authorizedOrchestrators[msg.sender] = true;

        emit OrchestratorStatusUpdated(
            msg.sender,
            true,
            block.timestamp
        );
    }

    function checkAuthorization(
        address user,
        bytes32 assetId,
        uint256 actionMask
    )
        public
        view
        returns (
            bool allowed,
            DenialReason reason
        )
    {
        if (!_isSingleAction(actionMask)) {
            return (false, DenialReason.InvalidAction);
        }

        if (!userRegistry.isActiveUser(user)) {
            return (
                false,
                DenialReason.UserInactiveOrMissing
            );
        }

        if (!assetPolicyRegistry.assetExists(assetId)) {
            return (false, DenialReason.AssetMissing);
        }

        if (
            !assetPolicyRegistry.policyExists(assetId) ||
            !assetPolicyRegistry.isAssetPolicyActive(assetId)
        ) {
            return (
                false,
                DenialReason.PolicyMissingOrInactive
            );
        }

        uint8 userGroup = userRegistry.getUserGroup(user);
        (uint8 assetType, , , , bool assetActive, , ) =
            assetPolicyRegistry.getAsset(assetId);

        if (!assetActive) {
            return (
                false,
                DenialReason.PolicyMissingOrInactive
            );
        }

        if (
            !entitlementRegistry.isActionAllowed(
                userGroup,
                assetType,
                actionMask
            )
        ) {
            return (
                false,
                DenialReason.PlatformEntitlementDenied
            );
        }

        if (
            !assetPolicyRegistry.isActionPermitted(
                assetId,
                userGroup,
                actionMask
            )
        ) {
            return (
                false,
                DenialReason.AssetPolicyDenied
            );
        }

        return (true, DenialReason.None);
    }

    function authorizeAndIssueLicense(
        bytes32 requestId,
        address user,
        bytes32 assetId,
        uint256 actionMask
    )
        external
        onlyAuthorizedOrchestrator
        returns (bytes32 licenseId)
    {
        if (requestId == bytes32(0)) {
            revert InvalidRequestId();
        }
        if (user == address(0)) {
            revert InvalidAddress();
        }
        if (assetId == bytes32(0)) {
            revert InvalidAssetId();
        }
        if (!_isSingleAction(actionMask)) {
            revert InvalidAction();
        }
        if (requestToLicense[requestId] != bytes32(0)) {
            revert RequestAlreadyProcessed();
        }

        AuthorizationContext memory context =
            _authorizeAndLoadContext(
                user,
                assetId,
                actionMask
            );

        licenseId = keccak256(
            abi.encode(
                requestId,
                user,
                assetId,
                actionMask,
                block.chainid,
                address(this)
            )
        );

        uint64 issuedAt = uint64(block.timestamp);

        License storage license = licenses[licenseId];
        license.licenseId = licenseId;
        license.requestId = requestId;
        license.user = user;
        license.assetOwner = context.assetOwner;
        license.issuedBy = msg.sender;
        license.assetId = assetId;
        license.assetType = context.assetType;
        license.userGroup = context.userGroup;
        license.actionMask = actionMask;
        license.assetPolicyHash = context.assetPolicyHash;
        license.assetPolicyVersion = context.assetPolicyVersion;
        license.entitlementVersion = context.entitlementVersion;
        license.issuedAt = issuedAt;
        license.validUntil = context.policyValidUntil;
        license.exists = true;

        requestToLicense[requestId] = licenseId;
        totalLicenses += 1;

        emit LicenseIssued(
            licenseId,
            requestId,
            user,
            assetId,
            context.assetType,
            context.userGroup,
            actionMask,
            context.assetPolicyHash,
            context.assetPolicyVersion,
            context.entitlementVersion,
            issuedAt,
            context.policyValidUntil
        );

        return licenseId;
    }

    function getLicense(
        bytes32 licenseId
    ) external view returns (License memory) {
        License memory license = licenses[licenseId];

        if (!license.exists) {
            revert LicenseNotFound();
        }

        return license;
    }

    function getLicenseByRequest(
        bytes32 requestId
    ) external view returns (License memory) {
        bytes32 licenseId = requestToLicense[requestId];

        if (licenseId == bytes32(0)) {
            revert LicenseNotFound();
        }

        return licenses[licenseId];
    }

    function getLicenseIdForRequest(
        bytes32 requestId
    ) external view returns (bytes32) {
        return requestToLicense[requestId];
    }

    function isRequestProcessed(
        bytes32 requestId
    ) external view returns (bool) {
        return requestToLicense[requestId] != bytes32(0);
    }

    function licenseExists(
        bytes32 licenseId
    ) external view returns (bool) {
        return licenses[licenseId].exists;
    }

    function setOrchestratorStatus(
        address orchestrator,
        bool authorized
    ) external onlyPlatformAdmin {
        if (orchestrator == address(0)) {
            revert InvalidAddress();
        }

        if (
            authorizedOrchestrators[orchestrator] ==
            authorized
        ) {
            revert SameStatus();
        }

        authorizedOrchestrators[orchestrator] = authorized;

        emit OrchestratorStatusUpdated(
            orchestrator,
            authorized,
            block.timestamp
        );
    }

    function transferPlatformAdmin(
        address newAdmin
    ) external onlyPlatformAdmin {
        if (newAdmin == address(0)) {
            revert InvalidAddress();
        }

        address previousAdmin = platformAdmin;
        platformAdmin = newAdmin;

        emit PlatformAdminTransferred(
            previousAdmin,
            newAdmin
        );
    }

    function _authorizeAndLoadContext(
        address user,
        bytes32 assetId,
        uint256 actionMask
    ) internal view returns (AuthorizationContext memory context) {
        if (!userRegistry.isActiveUser(user)) {
            revert UserInactiveOrMissing();
        }

        if (!assetPolicyRegistry.assetExists(assetId)) {
            revert AssetMissing();
        }

        if (
            !assetPolicyRegistry.policyExists(assetId) ||
            !assetPolicyRegistry.isAssetPolicyActive(assetId)
        ) {
            revert PolicyMissingOrInactive();
        }

        context.userGroup = userRegistry.getUserGroup(user);

        bool assetActive;

        (
            context.assetType,
            context.assetOwner,
            ,
            ,
            assetActive,
            ,

        ) = assetPolicyRegistry.getAsset(assetId);

        if (!assetActive) {
            revert PolicyMissingOrInactive();
        }

        if (
            !entitlementRegistry.isActionAllowed(
                context.userGroup,
                context.assetType,
                actionMask
            )
        ) {
            revert PlatformEntitlementDenied();
        }

        if (
            !assetPolicyRegistry.isActionPermitted(
                assetId,
                context.userGroup,
                actionMask
            )
        ) {
            revert AssetPolicyDenied();
        }

        (
            ,
            context.entitlementVersion,
            ,
            ,

        ) = entitlementRegistry.getEntitlement(
            context.userGroup,
            context.assetType
        );

        (
            context.assetPolicyHash,
            ,
            ,
            context.policyValidUntil,
            context.assetPolicyVersion,
            ,
            ,

        ) = assetPolicyRegistry.getPolicy(assetId);
    }

    function _isSingleAction(
        uint256 actionMask
    ) internal pure returns (bool) {
        return (
            actionMask == 1 ||
            actionMask == 2 ||
            actionMask == 4
        );
    }
}
