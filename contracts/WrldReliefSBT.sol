// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";

contract WrldReliefSBT is 
    Initializable,
    ERC721Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;
    
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    enum SBTType { DONOR, RECIPIENT }
    
    struct SBTData {
        uint256 tokenId;
        address holder;
        SBTType sbtType;
        uint256 campaignId;
        string disasterId;
        uint256 amount;
        string supportItem; // For recipient SBT
        uint256 issuedAt;
        string metadataURI;
    }
    
    CountersUpgradeable.Counter private _tokenIdCounter;
    
    mapping(uint256 => SBTData) public sbtData;
    mapping(address => uint256[]) public sbtsByHolder;
    mapping(uint256 => uint256[]) public sbtsByCampaign;
    mapping(string => uint256[]) public sbtsByDisaster;
    
    // Events
    event SBTMinted(
        uint256 indexed tokenId,
        address indexed holder,
        SBTType sbtType,
        uint256 campaignId,
        string disasterId,
        uint256 amount,
        uint256 timestamp
    );
    
    event SBTBurned(
        uint256 indexed tokenId,
        address indexed holder,
        uint256 timestamp
    );
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    function initialize() public initializer {
        __ERC721_init("Wrld Relief Soulbound Token", "WRLSBT");
        __AccessControl_init();
        __Pausable_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }
    
    /**
     * @notice Mints donor SBT
     * @param recipient Recipient address
     * @param campaignId Campaign ID
     * @param disasterId Disaster ID
     * @param amount Donated amount
     */
    function mintDonorSBT(
        address recipient,
        uint256 campaignId,
        string memory disasterId,
        uint256 amount
    ) 
        external 
        onlyRole(MINTER_ROLE) 
        whenNotPaused 
        returns (uint256) 
    {
        require(recipient != address(0), "Invalid recipient address");
        require(campaignId > 0, "Invalid campaign ID");
        require(bytes(disasterId).length > 0, "Disaster ID required");
        require(amount > 0, "Amount must be greater than 0");
        
        _tokenIdCounter.increment();
        uint256 tokenId = _tokenIdCounter.current();
        
        // SBT minting
        _safeMint(recipient, tokenId);
        
        // SBT data storage
        sbtData[tokenId] = SBTData({
            tokenId: tokenId,
            holder: recipient,
            sbtType: SBTType.DONOR,
            campaignId: campaignId,
            disasterId: disasterId,
            amount: amount,
            supportItem: "",
            issuedAt: block.timestamp,
            metadataURI: _generateDonorMetadata(campaignId, disasterId, amount)
        });
        
        // Indexing
        sbtsByHolder[recipient].push(tokenId);
        sbtsByCampaign[campaignId].push(tokenId);
        sbtsByDisaster[disasterId].push(tokenId);
        
        emit SBTMinted(
            tokenId,
            recipient,
            SBTType.DONOR,
            campaignId,
            disasterId,
            amount,
            block.timestamp
        );
        
        return tokenId;
    }
    
    /**
     * @notice Mints recipient SBT
     * @param recipient Recipient address
     * @param campaignId Campaign ID
     * @param disasterId Disaster ID
     * @param supportItem Support item
     * @param amount Amount
     */
    function mintRecipientSBT(
        address recipient,
        uint256 campaignId,
        string memory disasterId,
        string memory supportItem,
        uint256 amount
    ) 
        external 
        onlyRole(MINTER_ROLE) 
        whenNotPaused 
        returns (uint256) 
    {
        require(recipient != address(0), "Invalid recipient address");
        require(campaignId > 0, "Invalid campaign ID");
        require(bytes(disasterId).length > 0, "Disaster ID required");
        require(bytes(supportItem).length > 0, "Support item required");
        require(amount > 0, "Amount must be greater than 0");
        
        _tokenIdCounter.increment();
        uint256 tokenId = _tokenIdCounter.current();
        
        // SBT minting
        _safeMint(recipient, tokenId);
        
        // SBT data storage
        sbtData[tokenId] = SBTData({
            tokenId: tokenId,
            holder: recipient,
            sbtType: SBTType.RECIPIENT,
            campaignId: campaignId,
            disasterId: disasterId,
            amount: amount,
            supportItem: supportItem,
            issuedAt: block.timestamp,
            metadataURI: _generateRecipientMetadata(campaignId, disasterId, supportItem, amount)
        });
        
        // Indexing
        sbtsByHolder[recipient].push(tokenId);
        sbtsByCampaign[campaignId].push(tokenId);
        sbtsByDisaster[disasterId].push(tokenId);
        
        emit SBTMinted(
            tokenId,
            recipient,
            SBTType.RECIPIENT,
            campaignId,
            disasterId,
            amount,
            block.timestamp
        );
        
        return tokenId;
    }
    
    /**
     * @notice Burns SBT (only owner or admin)
     * @param tokenId Token ID
     */
    function burnSBT(uint256 tokenId) 
        external 
        whenNotPaused 
    {
        require(_exists(tokenId), "Token does not exist");
        address holder = ownerOf(tokenId);
        require(
            msg.sender == holder || hasRole(ADMIN_ROLE, msg.sender),
            "Not authorized to burn this token"
        );
        
        // Remove from indices
        _removeFromIndices(tokenId, holder);
        
        // Delete SBT data
        delete sbtData[tokenId];
        
        // Burn token
        _burn(tokenId);
        
        emit SBTBurned(tokenId, holder, block.timestamp);
    }
    
    /**
     * @notice Gets all SBTs by holder
     */
    function getSBTsByHolder(address holder) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return sbtsByHolder[holder];
    }
    
    /**
     * @notice Gets all SBTs by campaign
     */
    function getSBTsByCampaign(uint256 campaignId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return sbtsByCampaign[campaignId];
    }
    
    /**
     * @notice Gets all SBTs by disaster
     */
    function getSBTsByDisaster(string memory disasterId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return sbtsByDisaster[disasterId];
    }
    
    /**
     * @notice Gets SBT data
     */
    function getSBTData(uint256 tokenId) 
        external 
        view 
        returns (SBTData memory) 
    {
        require(_exists(tokenId), "Token does not exist");
        return sbtData[tokenId];
    }
    
    /**
     * @notice Returns token URI
     */
    function tokenURI(uint256 tokenId) 
        public 
        view 
        virtual 
        override 
        returns (string memory) 
    {
        require(_exists(tokenId), "Token does not exist");
        return sbtData[tokenId].metadataURI;
    }
    
    /**
     * @notice Returns total supply of SBTs
     */
    function totalSupply() public view returns (uint256) {
        return _tokenIdCounter.current();
    }
    
    // Internal functions
    function _generateDonorMetadata(
        uint256 campaignId,
        string memory disasterId,
        uint256 amount
    ) internal pure returns (string memory) {
        // JSON metadata 생성
        return string(abi.encodePacked(
            '{',
            '"name":"WRLD Relief Donor SBT #', uint2str(campaignId), '-', disasterId, '",',
            '"description":"This Soulbound Token represents a donation to the WRLD Relief campaign for disaster relief efforts.",',
            '"attributes":[',
                '{"trait_type":"Type","value":"Donor"},',
                '{"trait_type":"Campaign ID","value":', uint2str(campaignId), '},',
                '{"trait_type":"Disaster ID","value":"', disasterId, '"},',
                '{"trait_type":"Donation Amount","value":', uint2str(amount), '},',
                '{"trait_type":"Token Type","value":"Soulbound"}',
            '],',
            '"image":"https://app.wrldrelief.org/api/nft/donor/', uint2str(campaignId), '/', disasterId, '/', uint2str(amount), '"',
            '}'
        ));
    }
    
    function _generateRecipientMetadata(
        uint256 campaignId,
        string memory disasterId,
        string memory supportItem,
        uint256 amount
    ) internal pure returns (string memory) {
        // JSON metadata 생성
        return string(abi.encodePacked(
            '{',
            '"name":"WRLD Relief Recipient SBT #', uint2str(campaignId), '-', disasterId, '",',
            '"description":"This Soulbound Token represents aid received through the WRLD Relief campaign for disaster relief efforts.",',
            '"attributes":[',
                '{"trait_type":"Type","value":"Recipient"},',
                '{"trait_type":"Campaign ID","value":', uint2str(campaignId), '},',
                '{"trait_type":"Disaster ID","value":"', disasterId, '"},',
                '{"trait_type":"Support Item","value":"', supportItem, '"},',
                '{"trait_type":"Aid Amount","value":', uint2str(amount), '},',
                '{"trait_type":"Token Type","value":"Soulbound"}',
            '],',
            '"image":"https://app.wrldrelief.org/api/nft/recipient/', uint2str(campaignId), '/', disasterId, '/', supportItem, '/', uint2str(amount), '"',
            '}'
        ));
    }
    
    function _removeFromIndices(uint256 tokenId, address holder) internal {
        SBTData memory data = sbtData[tokenId];
        
        // Remove from sbtsByHolder
        uint256[] storage holderSBTs = sbtsByHolder[holder];
        for (uint256 i = 0; i < holderSBTs.length; i++) {
            if (holderSBTs[i] == tokenId) {
                holderSBTs[i] = holderSBTs[holderSBTs.length - 1];
                holderSBTs.pop();
                break;
            }
        }
        
        // Remove from sbtsByCampaign
        uint256[] storage campaignSBTs = sbtsByCampaign[data.campaignId];
        for (uint256 i = 0; i < campaignSBTs.length; i++) {
            if (campaignSBTs[i] == tokenId) {
                campaignSBTs[i] = campaignSBTs[campaignSBTs.length - 1];
                campaignSBTs.pop();
                break;
            }
        }
        
        // Remove from sbtsByDisaster
        uint256[] storage disasterSBTs = sbtsByDisaster[data.disasterId];
        for (uint256 i = 0; i < disasterSBTs.length; i++) {
            if (disasterSBTs[i] == tokenId) {
                disasterSBTs[i] = disasterSBTs[disasterSBTs.length - 1];
                disasterSBTs.pop();
                break;
            }
        }
    }
    
    function uint2str(uint256 _i) internal pure returns (string memory str) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0) {
            bstr[--k] = bytes1(uint8(48 + j % 10));
            j /= 10;
        }
        str = string(bstr);
    }
    
    // Override transfer functions to make tokens soulbound
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal virtual override {
        require(
            from == address(0) || to == address(0),
            "Soulbound tokens cannot be transferred"
        );
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }
    
    function approve(address, uint256) public virtual override {
        revert("Soulbound tokens cannot be approved");
    }
    
    function setApprovalForAll(address, bool) public virtual override {
        revert("Soulbound tokens cannot be approved");
    }
    
    function transferFrom(address, address, uint256) public virtual override {
        revert("Soulbound tokens cannot be transferred");
    }
    
    function safeTransferFrom(address, address, uint256) public virtual override {
        revert("Soulbound tokens cannot be transferred");
    }
    
    function safeTransferFrom(address, address, uint256, bytes memory) public virtual override {
        revert("Soulbound tokens cannot be transferred");
    }
    
    // Emergency functions
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
    
    // Required overrides
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
