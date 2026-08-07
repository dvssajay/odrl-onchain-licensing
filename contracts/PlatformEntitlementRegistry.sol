// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PlatformEntitlementRegistry
 * @notice Stores platform-defined permissions for each user group
 *         across hardware, datasets, and AI models.
 *
 * User Groups:
 * 1 = dAIEdge
 * 2 = NoE
 * 3 = AIoD
 * 4 = Other
 *
 * Asset Types:
 * 1 = Hardware
 * 2 = Dataset
 * 3 = AIModel
 *
 * Actions are represented as bitmasks.
 */
contract PlatformEntitlementRegistry {
    enum UserGroup {
        None,       // 0
        dAIEdge,    // 1
        NoE,        // 2
        AIoD,       // 3
        Other       // 4
    }

    enum AssetType {
        None,       // 0
        Hardware,   // 1
        Dataset,    // 2
        AIModel     // 3
    }

    struct Entitlement {
        uint256 actionMask;
        uint32 version;
        bool active;
        uint64 createdAt;
        uint64 updatedAt;
    }

    address public platformAdmin;

    mapping(UserGroup => mapping(AssetType => Entitlement))
        private entitlements;

    event EntitlementCreated(
        UserGroup indexed group,
        AssetType indexed assetType,
        uint256 actionMask,
        uint32 version,
        uint256 timestamp
    );

    event EntitlementUpdated(
        UserGroup indexed group,
        AssetType indexed assetType,
        uint256 previousMask,
        uint256 newMask,
        uint32 version,
        uint256 timestamp
    );

    event EntitlementStatusUpdated(
        UserGroup indexed group,
        AssetType indexed assetType,
        bool active,
        uint256 timestamp
    );

    event PlatformAdminTransferred(
        address indexed previousAdmin,
        address indexed newAdmin
    );

    error NotPlatformAdmin();
    error InvalidAddress();
    error InvalidUserGroup();
    error InvalidAssetType();
    error InvalidActionMask();
    error EntitlementAlreadyExists();
    error EntitlementNotFound();
    error SameActionMask();
    error SameStatus();

    modifier onlyPlatformAdmin() {
        if (msg.sender != platformAdmin) {
            revert NotPlatformAdmin();
        }
        _;
    }

    constructor() {
        platformAdmin = msg.sender;
    }

    /**
     * @notice Create a new platform entitlement.
     * @param group User group ID.
     * @param assetType Asset type ID.
     * @param actionMask Bitmask representing allowed actions.
     */
    function createEntitlement(
        UserGroup group,
        AssetType assetType,
        uint256 actionMask
    ) external onlyPlatformAdmin {
        _validateGroup(group);
        _validateAssetType(assetType);
        _validateActionMask(assetType, actionMask);

        Entitlement storage entitlement =
            entitlements[group][assetType];

        if (entitlement.createdAt != 0) {
            revert EntitlementAlreadyExists();
        }

        uint64 currentTime = uint64(block.timestamp);

        entitlements[group][assetType] = Entitlement({
            actionMask: actionMask,
            version: 1,
            active: true,
            createdAt: currentTime,
            updatedAt: currentTime
        });

        emit EntitlementCreated(
            group,
            assetType,
            actionMask,
            1,
            block.timestamp
        );
    }

    /**
     * @notice Update the action mask of an existing entitlement.
     */
    function updateEntitlement(
        UserGroup group,
        AssetType assetType,
        uint256 newActionMask
    ) external onlyPlatformAdmin {
        _validateGroup(group);
        _validateAssetType(assetType);
        _validateActionMask(assetType, newActionMask);

        Entitlement storage entitlement =
            entitlements[group][assetType];

        if (entitlement.createdAt == 0) {
            revert EntitlementNotFound();
        }

        if (entitlement.actionMask == newActionMask) {
            revert SameActionMask();
        }

        uint256 previousMask = entitlement.actionMask;

        entitlement.actionMask = newActionMask;
        entitlement.version += 1;
        entitlement.updatedAt = uint64(block.timestamp);

        emit EntitlementUpdated(
            group,
            assetType,
            previousMask,
            newActionMask,
            entitlement.version,
            block.timestamp
        );
    }

    /**
     * @notice Activate or deactivate an entitlement.
     */
    function setEntitlementStatus(
        UserGroup group,
        AssetType assetType,
        bool active
    ) external onlyPlatformAdmin {
        _validateGroup(group);
        _validateAssetType(assetType);

        Entitlement storage entitlement =
            entitlements[group][assetType];

        if (entitlement.createdAt == 0) {
            revert EntitlementNotFound();
        }

        if (entitlement.active == active) {
            revert SameStatus();
        }

        entitlement.active = active;
        entitlement.updatedAt = uint64(block.timestamp);

        emit EntitlementStatusUpdated(
            group,
            assetType,
            active,
            block.timestamp
        );
    }

    /**
     * @notice Check whether a group may perform an action.
     * @param actionMask Single action bit to check.
     */
    function isActionAllowed(
        UserGroup group,
        AssetType assetType,
        uint256 actionMask
    ) external view returns (bool) {
        _validateGroup(group);
        _validateAssetType(assetType);

        Entitlement memory entitlement =
            entitlements[group][assetType];

        if (entitlement.createdAt == 0 || !entitlement.active) {
            return false;
        }

        return
            actionMask != 0 &&
            (entitlement.actionMask & actionMask) == actionMask;
    }

    /**
     * @notice Return the full entitlement record.
     */
    function getEntitlement(
        UserGroup group,
        AssetType assetType
    )
        external
        view
        returns (
            uint256 actionMask,
            uint32 version,
            bool active,
            uint64 createdAt,
            uint64 updatedAt
        )
    {
        _validateGroup(group);
        _validateAssetType(assetType);

        Entitlement memory entitlement =
            entitlements[group][assetType];

        if (entitlement.createdAt == 0) {
            revert EntitlementNotFound();
        }

        return (
            entitlement.actionMask,
            entitlement.version,
            entitlement.active,
            entitlement.createdAt,
            entitlement.updatedAt
        );
    }

    /**
     * @notice Return only the stored action mask.
     */
    function getActionMask(
        UserGroup group,
        AssetType assetType
    ) external view returns (uint256) {
        _validateGroup(group);
        _validateAssetType(assetType);

        Entitlement memory entitlement =
            entitlements[group][assetType];

        if (entitlement.createdAt == 0) {
            revert EntitlementNotFound();
        }

        return entitlement.actionMask;
    }

    /**
     * @notice Return whether an entitlement exists.
     */
    function entitlementExists(
        UserGroup group,
        AssetType assetType
    ) external view returns (bool) {
        return entitlements[group][assetType].createdAt != 0;
    }

    /**
     * @notice Transfer platform administrator authority.
     */
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
        UserGroup group
    ) internal pure {
        if (group == UserGroup.None) {
            revert InvalidUserGroup();
        }
    }

    function _validateAssetType(
        AssetType assetType
    ) internal pure {
        if (assetType == AssetType.None) {
            revert InvalidAssetType();
        }
    }

    /**
     * @dev For the initial prototype, each asset type supports three actions.
     *      Valid masks are therefore from 1 to 7.
     */
    function _validateActionMask(
        AssetType assetType,
        uint256 actionMask
    ) internal pure {
        if (assetType == AssetType.None) {
            revert InvalidAssetType();
        }

        if (actionMask == 0 || actionMask > 7) {
            revert InvalidActionMask();
        }
    }
}