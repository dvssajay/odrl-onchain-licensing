// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title UserRegistry
 * @notice Registers platform users and assigns them to predefined user groups.
 *
 * Group IDs:
 * 1 = Group1
 * 2 = Group2
 * 3 = Group3
 * 4 = Group4
 *
 * Only the platform administrator can register users,
 * change groups, activate users, or deactivate users.
 */
contract UserRegistry {
    enum UserGroup {
        None,       // 0
        Group1,     // 1
        Group2,     // 2
        Group3,     // 3
        Group4      // 4
    }

    struct User {
        bytes32 userId;
        UserGroup group;
        bool active;
        uint64 registeredAt;
        uint64 updatedAt;
    }

    address public platformAdmin;

    mapping(address => User) private users;

    event UserRegistered(
        address indexed userAddress,
        bytes32 indexed userId,
        UserGroup group,
        uint256 timestamp
    );

    event UserGroupUpdated(
        address indexed userAddress,
        UserGroup previousGroup,
        UserGroup newGroup,
        uint256 timestamp
    );

    event UserStatusUpdated(
        address indexed userAddress,
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
    error UserAlreadyRegistered();
    error UserNotRegistered();
    error SameUserGroup();
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
     * @notice Register a new user.
     * @param userAddress Ethereum address belonging to the user.
     * @param userId Off-chain user identifier converted to bytes32.
     * @param group Group ID: 1=Group1, 2=Group2, 3=Group3, 4=Group4.
     */
    function registerUser(
        address userAddress,
        bytes32 userId,
        UserGroup group
    ) external onlyPlatformAdmin {
        if (userAddress == address(0)) {
            revert InvalidAddress();
        }

        if (group == UserGroup.None) {
            revert InvalidUserGroup();
        }

        if (users[userAddress].registeredAt != 0) {
            revert UserAlreadyRegistered();
        }

        uint64 currentTime = uint64(block.timestamp);

        users[userAddress] = User({
            userId: userId,
            group: group,
            active: true,
            registeredAt: currentTime,
            updatedAt: currentTime
        });

        emit UserRegistered(
            userAddress,
            userId,
            group,
            block.timestamp
        );
    }

    /**
     * @notice Change the group assigned to an existing user.
     */
    function updateUserGroup(
        address userAddress,
        UserGroup newGroup
    ) external onlyPlatformAdmin {
        User storage user = users[userAddress];

        if (user.registeredAt == 0) {
            revert UserNotRegistered();
        }

        if (newGroup == UserGroup.None) {
            revert InvalidUserGroup();
        }

        if (user.group == newGroup) {
            revert SameUserGroup();
        }

        UserGroup previousGroup = user.group;

        user.group = newGroup;
        user.updatedAt = uint64(block.timestamp);

        emit UserGroupUpdated(
            userAddress,
            previousGroup,
            newGroup,
            block.timestamp
        );
    }

    /**
     * @notice Activate or deactivate a registered user.
     */
    function setUserStatus(
        address userAddress,
        bool active
    ) external onlyPlatformAdmin {
        User storage user = users[userAddress];

        if (user.registeredAt == 0) {
            revert UserNotRegistered();
        }

        if (user.active == active) {
            revert SameStatus();
        }

        user.active = active;
        user.updatedAt = uint64(block.timestamp);

        emit UserStatusUpdated(
            userAddress,
            active,
            block.timestamp
        );
    }

    /**
     * @notice Returns the complete stored user record.
     */
    function getUser(
        address userAddress
    )
        external
        view
        returns (
            bytes32 userId,
            UserGroup group,
            bool active,
            uint64 registeredAt,
            uint64 updatedAt
        )
    {
        User memory user = users[userAddress];

        if (user.registeredAt == 0) {
            revert UserNotRegistered();
        }

        return (
            user.userId,
            user.group,
            user.active,
            user.registeredAt,
            user.updatedAt
        );
    }

    /**
     * @notice Returns the user's group.
     * @dev This will later be called by the authorization contract.
     */
    function getUserGroup(
        address userAddress
    ) external view returns (UserGroup) {
        User memory user = users[userAddress];

        if (user.registeredAt == 0) {
            revert UserNotRegistered();
        }

        return user.group;
    }

    /**
     * @notice Returns whether a user is registered and active.
     */
    function isActiveUser(
        address userAddress
    ) external view returns (bool) {
        User memory user = users[userAddress];

        return user.registeredAt != 0 && user.active;
    }

    /**
     * @notice Returns whether an address has been registered.
     */
    function isRegistered(
        address userAddress
    ) external view returns (bool) {
        return users[userAddress].registeredAt != 0;
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
}
