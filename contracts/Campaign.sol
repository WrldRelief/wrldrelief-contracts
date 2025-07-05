// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Campaign is 
    Initializable, 
    AccessControlUpgradeable, 
    PausableUpgradeable,
    ReentrancyGuardUpgradeable 
{
    using SafeERC20 for IERC20;
    
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ORGANIZER_ROLE = keccak256("ORGANIZER_ROLE");
    
    enum CampaignStatus { ACTIVE, PAUSED, ENDED, CANCELLED }
    
    struct CampaignData {
        uint256 id;
        string disasterId;
        address organizer;
        string name;
        string description;
        uint256 startDate;
        uint256 endDate;
        string[] supportItems;
        string imageUrl;
        CampaignStatus status;
        uint256 totalDonations;
        uint256 createdAt;
        bool canEdit;
    }
    
    struct Donation {
        address donor;
        uint256 amount;
        uint256 timestamp;
        string donorWorldIdName;
    }
    
    struct Distribution {
        address recipient;
        string supportItem;
        uint256 amount;
        uint256 timestamp;
        bool completed;
    }
    
    // State variables
    CampaignData public campaignData;
    IERC20 public usdcToken;
    address public userContract;
    address public sbtContract;
    
    mapping(uint256 => Donation) public donations;
    mapping(address => uint256[]) public donationsByUser;
    uint256 public nextDonationId;
    
    mapping(uint256 => Distribution) public distributions;
    mapping(address => uint256[]) public distributionsByRecipient;
    uint256 public nextDistributionId;
    
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 3; // 3%
    
    // Events
    event DonationReceived(
        uint256 indexed donationId,
        address indexed donor,
        uint256 amount,
        uint256 netAmount,
        uint256 feeAmount,
        uint256 timestamp
    );
    
    event DistributionExecuted(
        uint256 indexed distributionId,
        address indexed recipient,
        string supportItem,
        uint256 amount,
        uint256 timestamp
    );
    
    event CampaignStatusChanged(
        CampaignStatus oldStatus,
        CampaignStatus newStatus,
        uint256 timestamp
    );
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    function initialize(
        uint256 _id,
        string memory _disasterId,
        address _organizer,
        string memory _name,
        string memory _description,
        uint256 _startDate,
        uint256 _endDate,
        string[] memory _supportItems,
        string memory _imageUrl,
        address _userContract
    ) public initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        
        campaignData = CampaignData({
            id: _id,
            disasterId: _disasterId,
            organizer: _organizer,
            name: _name,
            description: _description,
            startDate: _startDate,
            endDate: _endDate,
            supportItems: _supportItems,
            imageUrl: _imageUrl,
            status: CampaignStatus.ACTIVE,
            totalDonations: 0,
            createdAt: block.timestamp,
            canEdit: true
        });
        
        userContract = _userContract;
        nextDonationId = 1;
        nextDistributionId = 1;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(ORGANIZER_ROLE, _organizer);
    }
    
    modifier onlyActiveStatus() {
        require(campaignData.status == CampaignStatus.ACTIVE, "Campaign not active");
        _;
    }
    
    modifier onlyDuringCampaign() {
        require(
            block.timestamp >= campaignData.startDate && 
            block.timestamp <= campaignData.endDate,
            "Campaign not in valid time period"
        );
        _;
    }
    
    modifier onlyVerifiedUser() {
        require(
            IWrldReliefUser(userContract).userRoles(msg.sender, IWrldReliefUser.UserRole.DONOR) ||
            IWrldReliefUser(userContract).userRoles(msg.sender, IWrldReliefUser.UserRole.RECIPIENT),
            "User not verified or missing role"
        );
        _;
    }
    
    /**
     * @notice Sets the USDC token address
     * @param _usdcToken USDC token contract address
     */
    function setUSDCToken(address _usdcToken) external onlyRole(ADMIN_ROLE) {
        require(_usdcToken != address(0), "Invalid USDC token address");
        usdcToken = IERC20(_usdcToken);
    }
    
    /**
     * @notice Sets the SBT contract address
     * @param _sbtContract SBT contract address
     */
    function setSBTContract(address _sbtContract) external onlyRole(ADMIN_ROLE) {
        require(_sbtContract != address(0), "Invalid SBT contract address");
        sbtContract = _sbtContract;
    }
    
    /**
     * @notice Donates USDC to the campaign
     * @param amount Amount of USDC to donate (18 decimals)
     */
    function donate(uint256 amount) 
        external 
        onlyActiveStatus 
        onlyDuringCampaign 
        onlyVerifiedUser 
        nonReentrant 
        whenNotPaused 
    {
        require(amount > 0, "Donation amount must be greater than 0");
        require(address(usdcToken) != address(0), "USDC token not set");
        
        // Platform fee calculation (3%)
        uint256 feeAmount = (amount * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 netAmount = amount - feeAmount;
        
        // USDC transfer (donor → this contract)
        usdcToken.safeTransferFrom(msg.sender, address(this), amount);
        
        // Donation record creation
        uint256 donationId = nextDonationId++;
        
        // Donor information retrieval
        (string memory worldIdName,,,,,,,,) = IWrldReliefUser(userContract).getUserInfo(msg.sender);
        
        donations[donationId] = Donation({
            donor: msg.sender,
            amount: netAmount,
            timestamp: block.timestamp,
            donorWorldIdName: worldIdName
        });
        
        donationsByUser[msg.sender].push(donationId);
        campaignData.totalDonations += netAmount;
        
        // Remove edit permission (after donation)
        if (campaignData.canEdit) {
            campaignData.canEdit = false;
        }
        
        // Update user donation amount
        IWrldReliefUser(userContract).updateDonationAmount(msg.sender, netAmount);
        
        // Issue donor SBT (automatically)
        if (sbtContract != address(0)) {
            ISBTContract(sbtContract).mintDonorSBT(
                msg.sender,
                campaignData.id,
                campaignData.disasterId,
                netAmount
            );
        }
        
        emit DonationReceived(
            donationId,
            msg.sender,
            amount,
            netAmount,
            feeAmount,
            block.timestamp
        );
    }
    
    /**
     * @notice Distributes support items/services to recipients
     * @param recipient Recipient address
     * @param supportItem Support item/service
     * @param amount Amount to distribute
     */
    function distribute(
        address recipient,
        string memory supportItem,
        uint256 amount
    ) 
        external 
        onlyRole(ORGANIZER_ROLE) 
        nonReentrant 
        whenNotPaused 
    {
        require(recipient != address(0), "Invalid recipient address");
        require(bytes(supportItem).length > 0, "Support item required");
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= campaignData.totalDonations, "Insufficient campaign funds");
        
        // Verify recipient is a registered user
        require(
            IWrldReliefUser(userContract).userRoles(recipient, IWrldReliefUser.UserRole.RECIPIENT),
            "Recipient not verified"
        );
        
        uint256 distributionId = nextDistributionId++;
        
        distributions[distributionId] = Distribution({
            recipient: recipient,
            supportItem: supportItem,
            amount: amount,
            timestamp: block.timestamp,
            completed: true
        });
        
        distributionsByRecipient[recipient].push(distributionId);
        campaignData.totalDonations -= amount;
        
        // USDC transfer (to recipient)
        usdcToken.safeTransfer(recipient, amount);
        
        // Update recipient donation amount
        IWrldReliefUser(userContract).updateReceivedAmount(recipient, amount);
        
        // Issue recipient SBT (automatically)
        if (sbtContract != address(0)) {
            ISBTContract(sbtContract).mintRecipientSBT(
                recipient,
                campaignData.id,
                campaignData.disasterId,
                supportItem,
                amount
            );
        }
        
        emit DistributionExecuted(
            distributionId,
            recipient,
            supportItem,
            amount,
            block.timestamp
        );
    }
    
    /**
     * @notice Updates campaign information (only possible before donations received)
     * @param description New description
     * @param imageUrl New image URL
     */
    function updateCampaign(
        string memory description,
        string memory imageUrl
    ) 
        external 
        onlyRole(ORGANIZER_ROLE) 
        whenNotPaused 
    {
        require(campaignData.canEdit, "Cannot edit after donations received");
        
        campaignData.description = description;
        campaignData.imageUrl = imageUrl;
    }
    
    /**
     * @notice Changes campaign status
     * @param newStatus New status
     */
    function changeStatus(CampaignStatus newStatus) 
        external 
        onlyRole(ORGANIZER_ROLE) 
        whenNotPaused 
    {
        require(newStatus != campaignData.status, "Status already set");
        
        CampaignStatus oldStatus = campaignData.status;
        campaignData.status = newStatus;
        
        emit CampaignStatusChanged(oldStatus, newStatus, block.timestamp);
    }
    
    /**
     * @notice Retrieves campaign information
     */
    function getCampaignInfo() 
        external 
        view 
        returns (
            uint256 id,
            string memory disasterId,
            address organizer,
            string memory name,
            string memory description,
            uint256 startDate,
            uint256 endDate,
            string[] memory supportItems,
            string memory imageUrl,
            CampaignStatus status,
            uint256 totalDonations,
            uint256 createdAt,
            bool canEdit
        ) 
    {
        return (
            campaignData.id,
            campaignData.disasterId,
            campaignData.organizer,
            campaignData.name,
            campaignData.description,
            campaignData.startDate,
            campaignData.endDate,
            campaignData.supportItems,
            campaignData.imageUrl,
            campaignData.status,
            campaignData.totalDonations,
            campaignData.createdAt,
            campaignData.canEdit
        );
    }
    
    /**
     * @notice Retrieves user's donations
     */
    function getDonationsByUser(address user) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return donationsByUser[user];
    }
    
    /**
     * @notice Retrieves recipient's distributions
     */
    function getDistributionsByRecipient(address recipient) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return distributionsByRecipient[recipient];
    }
    
    /**
     * @notice Retrieves specific donation information
     */
    function getDonation(uint256 donationId) 
        external 
        view 
        returns (Donation memory) 
    {
        return donations[donationId];
    }
    
    /**
     * @notice Retrieves specific distribution information
     */
    function getDistribution(uint256 distributionId) 
        external 
        view 
        returns (Distribution memory) 
    {
        return distributions[distributionId];
    }
    
    // Emergency functions
    function emergencyPause() external onlyRole(ADMIN_ROLE) {
        _pause();
        campaignData.status = CampaignStatus.PAUSED;
    }
    
    function emergencyUnpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
        campaignData.status = CampaignStatus.ACTIVE;
    }
    
    /**
     * @notice Withdraws funds in case of emergency
     */
    function emergencyWithdraw() external onlyRole(ADMIN_ROLE) {
        require(address(usdcToken) != address(0), "USDC token not set");
        uint256 balance = usdcToken.balanceOf(address(this));
        if (balance > 0) {
            usdcToken.safeTransfer(msg.sender, balance);
        }
    }
}

// Interfaces
interface IWrldReliefUser {
    enum UserRole { DONOR, RECIPIENT, ORGANIZER }
    
    function userRoles(address user, UserRole role) external view returns (bool);
    function getUserInfo(address user) external view returns (
        string memory, bool, bool, bool, bool, uint256, uint256, uint256, uint256
    );
    function updateDonationAmount(address user, uint256 amount) external;
    function updateReceivedAmount(address user, uint256 amount) external;
}

interface ISBTContract {
    function mintDonorSBT(
        address recipient,
        uint256 campaignId,
        string memory disasterId,
        uint256 amount
    ) external;
    
    function mintRecipientSBT(
        address recipient,
        uint256 campaignId,
        string memory disasterId,
        string memory supportItem,
        uint256 amount
    ) external;
}
