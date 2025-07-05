// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract WrldReliefUser is 
    Initializable, 
    AccessControlUpgradeable, 
    PausableUpgradeable,
    ReentrancyGuardUpgradeable 
{
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    
    enum UserRole { DONOR, RECIPIENT, ORGANIZER }
    
    struct User {
        string worldIdName;
        bool worldIdVerified;
        mapping(UserRole => bool) activeRoles;
        uint256 totalDonations;
        uint256 totalReceived;
        uint256 wrlhTokenBalance;
        uint256 createdAt;
    }
    
    struct RoleTransition {
        UserRole fromRole;
        UserRole toRole;
        uint256 timestamp;
        address triggeredBy;
        string reason;
    }
    
    // State variables
    mapping(address => User) public users;
    mapping(address => mapping(UserRole => bool)) public userRoles;
    mapping(address => RoleTransition[]) public roleHistory;
    mapping(address => uint256) public userCreationTime;
    
    // Events
    event UserRegistered(address indexed user, string worldIdName, uint256 timestamp);
    event UserVerified(address indexed user, uint256 timestamp);
    event RoleAssigned(address indexed user, UserRole role, uint256 timestamp);
    event RoleRevoked(address indexed user, UserRole role, uint256 timestamp);
    event RoleTransitioned(
        address indexed user, 
        UserRole fromRole, 
        UserRole toRole, 
        address triggeredBy,
        uint256 timestamp
    );
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    function initialize() public initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(VERIFIER_ROLE, msg.sender);
    }
    
    modifier userExists(address user) {
        require(users[user].createdAt > 0, "User does not exist");
        _;
    }
    
    modifier hasUserRole(UserRole role) {
        require(userRoles[msg.sender][role], "Missing required role");
        _;
    }
    
    /**
     * @notice Registers a new user
     * @param worldIdName Worldcoin name
     */
    function registerUser(string memory worldIdName) external whenNotPaused {
        require(users[msg.sender].createdAt == 0, "User already registered");
        require(bytes(worldIdName).length > 0, "WorldID name required");
        
        users[msg.sender].worldIdName = worldIdName;
        users[msg.sender].worldIdVerified = false;
        users[msg.sender].createdAt = block.timestamp;
        userCreationTime[msg.sender] = block.timestamp;
        
        emit UserRegistered(msg.sender, worldIdName, block.timestamp);
    }
    
    /**
     * @notice Verifies a user's World ID
     * @param user Address of the user to verify
     */
    function verifyWorldId(address user) 
        external 
        onlyRole(VERIFIER_ROLE) 
        userExists(user) 
        whenNotPaused 
    {
        require(!users[user].worldIdVerified, "User already verified");
        
        users[user].worldIdVerified = true;
        
        emit UserVerified(user, block.timestamp);
    }
    
    /**
     * @notice Assigns a role to a user
     * @param user Address of the user to assign the role to
     * @param role Role to assign
     */
    function assignRole(address user, UserRole role) 
        external 
        onlyRole(ADMIN_ROLE) 
        userExists(user) 
        whenNotPaused 
    {
        require(users[user].worldIdVerified, "User must be verified");
        require(!userRoles[user][role], "Role already assigned");
        
        userRoles[user][role] = true;
        users[user].activeRoles[role] = true;
        
        emit RoleAssigned(user, role, block.timestamp);
    }
    
    /**
     * @notice Revokes a role from a user
     * @param user Address of the user to revoke the role from
     * @param role Role to revoke
     */
    function revokeRole(address user, UserRole role) 
        external 
        onlyRole(ADMIN_ROLE) 
        userExists(user) 
        whenNotPaused 
    {
        require(userRoles[user][role], "Role not assigned");
        
        userRoles[user][role] = false;
        users[user].activeRoles[role] = false;
        
        emit RoleRevoked(user, role, block.timestamp);
    }
    
    /**
     * @notice Transitions a user's role (Donor ↔ Recipient)
     * @param fromRole Source role
     * @param toRole Target role
     * @param reason Reason for role transition
     */
    function transitionRole(UserRole fromRole, UserRole toRole, string memory reason) 
        external 
        userExists(msg.sender) 
        whenNotPaused 
    {
        require(userRoles[msg.sender][fromRole], "Does not have source role");
        require(!userRoles[msg.sender][toRole], "Already has target role");
        require(fromRole != toRole, "Source and target roles must be different");
        
        // Role transition history
        roleHistory[msg.sender].push(RoleTransition({
            fromRole: fromRole,
            toRole: toRole,
            timestamp: block.timestamp,
            triggeredBy: msg.sender,
            reason: reason
        }));
        
        // Role update
        userRoles[msg.sender][fromRole] = false;
        users[msg.sender].activeRoles[fromRole] = false;
        userRoles[msg.sender][toRole] = true;
        users[msg.sender].activeRoles[toRole] = true;
        
        emit RoleTransitioned(msg.sender, fromRole, toRole, msg.sender, block.timestamp);
    }
    
    /**
     * @notice Retrieves user information
     */
    function getUserInfo(address user) 
        external 
        view 
        returns (
            string memory worldIdName,
            bool worldIdVerified,
            bool isDonor,
            bool isRecipient,
            bool isOrganizer,
            uint256 totalDonations,
            uint256 totalReceived,
            uint256 wrlhTokenBalance,
            uint256 createdAt
        ) 
    {
        User storage userData = users[user];
        return (
            userData.worldIdName,
            userData.worldIdVerified,
            userData.activeRoles[UserRole.DONOR],
            userData.activeRoles[UserRole.RECIPIENT],
            userData.activeRoles[UserRole.ORGANIZER],
            userData.totalDonations,
            userData.totalReceived,
            userData.wrlhTokenBalance,
            userData.createdAt
        );
    }
    
    /**
     * @notice Retrieves a user's role transition history
     */
    function getRoleHistory(address user) 
        external 
        view 
        returns (RoleTransition[] memory) 
    {
        return roleHistory[user];
    }
    
    /**
     * @notice Updates a user's donation amount (only approved contracts)
     */
    function updateDonationAmount(address user, uint256 amount) 
        external 
        onlyRole(ADMIN_ROLE) 
        userExists(user) 
    {
        users[user].totalDonations += amount;
    }
    
    /**
     * @notice Updates a user's received amount (only approved contracts)
     */
    function updateReceivedAmount(address user, uint256 amount) 
        external 
        onlyRole(ADMIN_ROLE) 
        userExists(user) 
    {
        users[user].totalReceived += amount;
    }
    
    /**
     * @notice Updates a user's WRLH token balance (only approved contracts)
     */
    function updateWRLHBalance(address user, uint256 amount) 
        external 
        onlyRole(ADMIN_ROLE) 
        userExists(user) 
    {
        users[user].wrlhTokenBalance = amount;
    }
    
    // Emergency functions
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}
