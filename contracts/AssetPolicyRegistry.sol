// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title AssetPolicyRegistry
 * @notice Allows asset owners to register hardware resources,
 *         datasets, and AI models and define enforceable policies.
 *
 * Asset Types:
 * 1 = Hardware
 * 2 = Dataset
 * 3 = AIModel
 *
 * User-group array order:
 * index 0 = Group 1: dAIEdge
 * index 1 = Group 2: NoE
 * index 2 = Group 3: AIoD
 * index 3 = Group 4: Other
 *
 * Actions are represented as bitmasks:
 *
 * Hardware:
 * 1 = TYPE1
 * 2 = TYPE2
 * 4 = TYPE3
 *
 * Dataset:
 * 1 = ACCESS
 * 2 = TRAIN
 * 4 = DOWNLOAD
 *
 * AI Model:
 * 1 = INFERENCE
 * 2 = FINE_TUNE
 * 4 = DOWNLOAD
 */
contract AssetPolicyRegistry {
    enum AssetType {
        None,       // 0
        Hardware,   // 1
        Dataset,    // 2
        AIModel     // 3
    }

    struct Asset {
        bytes32 assetId;
        AssetType assetType;
        address owner;
        bytes32 metadataHash;
        string metadataURI;
        bool active;
        uint64 registeredAt;
        uint64 updatedAt;
    }

    struct Policy {
        bytes32 policyHash;
        string policyURI;

        // Group 1, Group 2, Group 3, Group 4
        uint256[4] permissionMasks;
        uint256[4] prohibitionMasks;

        uint64 validFrom;
        uint64 validUntil;
        uint32 version;
        bool active;
        uint64 createdAt;
        uint64 updatedAt;
    }

    address public platformAdmin;

    mapping(bytes32 => Asset) private assets;
    mapping(bytes32 => Policy) private policies;

    event AssetRegistered(
        bytes32 indexed assetId,
        AssetType indexed assetType,
        address indexed owner,
        bytes32 metadataHash,
        string metadataURI,
        uint256 timestamp
    );

    event AssetStatusUpdated(
        bytes32 indexed assetId,
        bool active,
        uint256 timestamp
    );

    event AssetOwnershipTransferred(
        bytes32 indexed assetId,
        address indexed previousOwner,
        address indexed newOwner,
        uint256 timestamp
    );

    event PolicyCreated(
        bytes32 indexed assetId,
        bytes32 indexed policyHash,
        uint32 version,
        uint64 validFrom,
        uint64 validUntil,
        uint256 timestamp
    );

    event PolicyUpdated(
        bytes32 indexed assetId,
        bytes32 indexed policyHash,
        uint32 version,
        uint64 validFrom,
        uint64 validUntil,
        uint256 timestamp
    );

    event PolicyStatusUpdated(
        bytes32 indexed assetId,
        bool active,
        uint256 timestamp
    );

    event PlatformAdminTransferred(
        address indexed previousAdmin,
        address indexed newAdmin
    );

    error NotPlatformAdmin();
    error NotAssetOwner();
    error InvalidAddress();
    error InvalidAssetId();
    error InvalidAssetType();
    error InvalidMetadataHash();
    error InvalidPolicyHash();
    error InvalidActionMask();
    error InvalidValidityPeriod();
    error InvalidUserGroup();
    error AssetAlreadyRegistered();
    error AssetNotFound();
    error AssetInactive();
    error PolicyAlreadyExists();
    error PolicyNotFound();
    error SameStatus();
    error SameOwner();
    

    modifier onlyPlatformAdmin() {
        if (msg.sender != platformAdmin) {
            revert NotPlatformAdmin();
        }
        _;
    }

    modifier onlyAssetOwner(bytes32 assetId) {
        Asset memory asset = assets[assetId];

        if (asset.registeredAt == 0) {
            revert AssetNotFound();
        }

        if (msg.sender != asset.owner) {
            revert NotAssetOwner();
        }

        _;
    }

    constructor() {
        platformAdmin = msg.sender;
    }

    /**
     * @notice Register a hardware resource, dataset, or AI model.
     *
     * @param assetId Unique asset identifier represented as bytes32.
     * @param assetType 1=Hardware, 2=Dataset, 3=AIModel.
     * @param metadataHash Hash of the off-chain asset metadata.
     * @param metadataURI URI pointing to the off-chain metadata.
     */
    function registerAsset(
        bytes32 assetId,
        AssetType assetType,
        bytes32 metadataHash,
        string calldata metadataURI
    ) external {
        if (assetId == bytes32(0)) {
            revert InvalidAssetId();
        }

        if (assetType == AssetType.None) {
            revert InvalidAssetType();
        }

        if (metadataHash == bytes32(0)) {
            revert InvalidMetadataHash();
        }

        if (assets[assetId].registeredAt != 0) {
            revert AssetAlreadyRegistered();
        }

        uint64 currentTime = uint64(block.timestamp);

        assets[assetId] = Asset({
            assetId: assetId,
            assetType: assetType,
            owner: msg.sender,
            metadataHash: metadataHash,
            metadataURI: metadataURI,
            active: true,
            registeredAt: currentTime,
            updatedAt: currentTime
        });

        emit AssetRegistered(
            assetId,
            assetType,
            msg.sender,
            metadataHash,
            metadataURI,
            block.timestamp
        );
    }

    /**
     * @notice Create the first enforceable policy for an asset.
     *
     * Array order:
     * [Group1, Group2, Group3, Group4]
     */
    function createPolicy(
        bytes32 assetId,
        bytes32 policyHash,
        string calldata policyURI,
        uint256[4] calldata permissionMasks,
        uint256[4] calldata prohibitionMasks,
        uint64 validFrom,
        uint64 validUntil
    ) external onlyAssetOwner(assetId) {
        Asset memory asset = assets[assetId];

        if (!asset.active) {
            revert AssetInactive();
        }

        if (policyHash == bytes32(0)) {
            revert InvalidPolicyHash();
        }

        if (policies[assetId].createdAt != 0) {
            revert PolicyAlreadyExists();
        }

        _validateMasks(permissionMasks);
        _validateMasks(prohibitionMasks);
        _validateValidity(validFrom, validUntil);

        uint64 currentTime = uint64(block.timestamp);

        policies[assetId] = Policy({
            policyHash: policyHash,
            policyURI: policyURI,
            permissionMasks: permissionMasks,
            prohibitionMasks: prohibitionMasks,
            validFrom: validFrom,
            validUntil: validUntil,
            version: 1,
            active: true,
            createdAt: currentTime,
            updatedAt: currentTime
        });

        emit PolicyCreated(
            assetId,
            policyHash,
            1,
            validFrom,
            validUntil,
            block.timestamp
        );
    }

    /**
     * @notice Replace the active policy representation with a new version.
     *
     * The policy version increments each time.
     * Historical changes remain visible through emitted blockchain events.
     */
    function updatePolicy(
        bytes32 assetId,
        bytes32 newPolicyHash,
        string calldata newPolicyURI,
        uint256[4] calldata newPermissionMasks,
        uint256[4] calldata newProhibitionMasks,
        uint64 newValidFrom,
        uint64 newValidUntil
    ) external onlyAssetOwner(assetId) {
        if (newPolicyHash == bytes32(0)) {
            revert InvalidPolicyHash();
        }

        Policy storage policy = policies[assetId];

        if (policy.createdAt == 0) {
            revert PolicyNotFound();
        }

        _validateMasks(newPermissionMasks);
        _validateMasks(newProhibitionMasks);
        _validateValidity(newValidFrom, newValidUntil);

        policy.policyHash = newPolicyHash;
        policy.policyURI = newPolicyURI;
        policy.permissionMasks = newPermissionMasks;
        policy.prohibitionMasks = newProhibitionMasks;
        policy.validFrom = newValidFrom;
        policy.validUntil = newValidUntil;
        policy.version += 1;
        policy.active = true;
        policy.updatedAt = uint64(block.timestamp);

        emit PolicyUpdated(
            assetId,
            newPolicyHash,
            policy.version,
            newValidFrom,
            newValidUntil,
            block.timestamp
        );
    }

    /**
     * @notice Activate or deactivate an asset.
     */
    function setAssetStatus(
        bytes32 assetId,
        bool active
    ) external onlyAssetOwner(assetId) {
        Asset storage asset = assets[assetId];

        if (asset.active == active) {
            revert SameStatus();
        }

        asset.active = active;
        asset.updatedAt = uint64(block.timestamp);

        emit AssetStatusUpdated(
            assetId,
            active,
            block.timestamp
        );
    }

    /**
     * @notice Activate or deactivate an asset policy.
     */
    function setPolicyStatus(
        bytes32 assetId,
        bool active
    ) external onlyAssetOwner(assetId) {
        Policy storage policy = policies[assetId];

        if (policy.createdAt == 0) {
            revert PolicyNotFound();
        }

        if (policy.active == active) {
            revert SameStatus();
        }

        policy.active = active;
        policy.updatedAt = uint64(block.timestamp);

        emit PolicyStatusUpdated(
            assetId,
            active,
            block.timestamp
        );
    }

    /**
     * @notice Transfer ownership of an asset.
     *
     * The new owner gains permission to update or deactivate the policy.
     */
    function transferAssetOwnership(
        bytes32 assetId,
        address newOwner
    ) external onlyAssetOwner(assetId) {
        if (newOwner == address(0)) {
            revert InvalidAddress();
        }

        Asset storage asset = assets[assetId];

        if (asset.owner == newOwner) {
            revert SameOwner();
        }

        address previousOwner = asset.owner;

        asset.owner = newOwner;
        asset.updatedAt = uint64(block.timestamp);

        emit AssetOwnershipTransferred(
            assetId,
            previousOwner,
            newOwner,
            block.timestamp
        );
    }

    /**
     * @notice Check whether an asset policy permits an action
     *         for a given user group.
     *
     * @param group Group ID from 1 to 4.
     * @param actionMask Action bit to check.
     */
    function isActionPermitted(
        bytes32 assetId,
        uint8 group,
        uint256 actionMask
    ) external view returns (bool) {
        _validateGroup(group);
        _validateSingleAction(actionMask);

        Asset memory asset = assets[assetId];

        if (asset.registeredAt == 0 || !asset.active) {
            return false;
        }

        Policy memory policy = policies[assetId];

        if (
            policy.createdAt == 0 ||
            !policy.active ||
            !_isPolicyCurrentlyValid(policy)
        ) {
            return false;
        }

        uint256 groupIndex = uint256(group - 1);

        bool permissionExists =
            (policy.permissionMasks[groupIndex] & actionMask) == actionMask;

        bool prohibitionExists =
            (policy.prohibitionMasks[groupIndex] & actionMask) == actionMask;

        return permissionExists && !prohibitionExists;
    }

    /**
     * @notice Return permission and prohibition masks for one user group.
     */
    function getGroupPolicyMasks(
        bytes32 assetId,
        uint8 group
    )
        external
        view
        returns (
            uint256 permissionMask,
            uint256 prohibitionMask
        )
    {
        _validateGroup(group);

        Policy memory policy = policies[assetId];

        if (policy.createdAt == 0) {
            revert PolicyNotFound();
        }

        uint256 groupIndex = uint256(group - 1);

        return (
            policy.permissionMasks[groupIndex],
            policy.prohibitionMasks[groupIndex]
        );
    }

    /**
     * @notice Return the complete asset record.
     */
    function getAsset(
        bytes32 assetId
    )
        external
        view
        returns (
            AssetType assetType,
            address owner,
            bytes32 metadataHash,
            string memory metadataURI,
            bool active,
            uint64 registeredAt,
            uint64 updatedAt
        )
    {
        Asset memory asset = assets[assetId];

        if (asset.registeredAt == 0) {
            revert AssetNotFound();
        }

        return (
            asset.assetType,
            asset.owner,
            asset.metadataHash,
            asset.metadataURI,
            asset.active,
            asset.registeredAt,
            asset.updatedAt
        );
    }

    /**
     * @notice Return the main policy information.
     */
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
        )
    {
        Policy memory policy = policies[assetId];

        if (policy.createdAt == 0) {
            revert PolicyNotFound();
        }

        return (
            policy.policyHash,
            policy.policyURI,
            policy.validFrom,
            policy.validUntil,
            policy.version,
            policy.active,
            policy.createdAt,
            policy.updatedAt
        );
    }

    function assetExists(
        bytes32 assetId
    ) external view returns (bool) {
        return assets[assetId].registeredAt != 0;
    }

    function policyExists(
        bytes32 assetId
    ) external view returns (bool) {
        return policies[assetId].createdAt != 0;
    }

    /**
     * @notice Return whether an asset and its policy are currently usable.
     */
    function isAssetPolicyActive(
        bytes32 assetId
    ) external view returns (bool) {
        Asset memory asset = assets[assetId];
        Policy memory policy = policies[assetId];

        if (
            asset.registeredAt == 0 ||
            !asset.active ||
            policy.createdAt == 0 ||
            !policy.active
        ) {
            return false;
        }

        return _isPolicyCurrentlyValid(policy);
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

    function _validateGroup(
        uint8 group
    ) internal pure {
        if (group < 1 || group > 4) {
            revert InvalidUserGroup();
        }
    }

    function _validateMasks(
        uint256[4] calldata masks
    ) internal pure {
        for (uint256 i = 0; i < 4; i++) {
            if (masks[i] > 7) {
                revert InvalidActionMask();
            }
        }
    }

    function _validateSingleAction(
        uint256 actionMask
    ) internal pure {
        if (
            actionMask != 1 &&
            actionMask != 2 &&
            actionMask != 4
        ) {
            revert InvalidActionMask();
        }
    }

    function _validateValidity(
        uint64 validFrom,
        uint64 validUntil
    ) internal pure {
        if (
            validUntil != 0 &&
            validUntil <= validFrom
        ) {
            revert InvalidValidityPeriod();
        }
    }

    function _isPolicyCurrentlyValid(
        Policy memory policy
    ) internal view returns (bool) {
        if (
            policy.validFrom != 0 &&
            block.timestamp < policy.validFrom
        ) {
            return false;
        }

        if (
            policy.validUntil != 0 &&
            block.timestamp > policy.validUntil
        ) {
            return false;
        }

        return true;
    }
}