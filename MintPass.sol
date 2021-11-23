// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.9.0;

// Afterparty MintPass allows buying a pass to acquite future collection pieces.


// Truffle imports
import "../openzeppelin-contracts/contracts/token/ERC1155/presets/ERC1155PresetMinterPauser.sol";
import "../openzeppelin-contracts/contracts/utils/math/SafeMath.sol";

// Remix imports
//import "@openzeppelin/contracts/token/ERC1155/presets/ERC1155PresetMinterPauser.sol";
//import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// Audits
// Last passed audits
// Mythrill: 5, 11/22/2021
// MythX:
// Optilistic :

contract MintPass is ERC1155PresetMinterPauser {
    using SafeMath for uint256;

    /***********************************|
    |        Structs                    |
    |__________________________________*/
    struct Collection {
        bytes32 name;   // short name (up to 32 bytes)
        uint16 collectionType;
        string uri;
        uint cost;
        uint256 maxMintCount;
        address artistPayableAddress;
    }

    struct Pass {
        address owner;
        uint sale_price;
    }

    struct WhitelistAddresses {
        // NOTE: uint256 = remaining_mint_count
        mapping(address => uint256) whitelist;
    }

    /***********************************|
    |        Variables and Constants    |
    |__________________________________*/
    uint16 public build = 6;
    uint256 public tokenCount = 0;
    uint16 public collectionCount = 0;

    // For Minting and Burning, locks the prices
    bool private _enabled = false;
    // For metadata (scripts), when locked, cannot be changed
    bool private _locked = false;

    bytes4 constant public ERC1155_ACCEPTED = 0xf23a6e61;


    address payable public contract_owner;

    mapping(uint256 => address) public tokenToAddress;
    mapping(address => uint256) public whitelist_simple;

    Pass[] public passes;
    Collection[] public collections;
    WhitelistAddresses[] private collectionWhitelists;


    /***********************************|
    |        Events                     |
    |__________________________________*/
    /**
     * @dev Emitted when an original NFT with a new seed is minted
     */
    event CreateCollection(address indexed to, uint256 seed, uint256 indexed originalsMinted);
    event MintOriginal(address indexed to, uint256 seed, uint256 indexed originalsMinted);
    event PassMinted(address _seller, address _buyer, uint256 _price);

    /**
     * @dev Emitted when an print is minted
     */
    event PassMintedFull(
        address indexed to,
        uint256 id,
        uint256 indexed seed,
        uint256 pricePaid,
        uint256 nextPrintPrice,
        uint256 nextBurnPrice,
        uint256 printsSupply,
        uint256 royaltyPaid,
        uint256 reserve,
        address indexed royaltyRecipient
    );


    /***********************************|
    |        Modifiers                  |
    |__________________________________*/
    modifier onlyWhenEnabled() {
        require(_enabled, "Contract is disabled");
        _;
    }
    modifier onlyWhenDisabled() {
        require(!_enabled, "Contract is enabled");
        _;
    }
    modifier onlyUnlocked() {
        require(!_locked, "Contract is locked");
        _;
    }

    modifier ownerorWhitelistOnly() {
        require(contract_owner == msg.sender);
        _;
    }



    /***********************************|
    |        MAIN CONSTRUCTOR           |
    |__________________________________*/
    constructor() ERC1155PresetMinterPauser("https://afterparty.ai/nft/{id}.json") {
        contract_owner = payable(msg.sender);
    }

    /***********************************|
    |        User Interactions          |
    |__________________________________*/
    /**
     * @dev Function to mint tokens. Msg.value must be sufficient
     */
    function mint(uint256 collectionId) public payable {
        require(collectionId < collections.length, "Collection not found");
        require(collections[collectionId].maxMintCount > 0, "No remaining passes to mint");

        require(msg.value >= collections[collectionId].cost, "Not enough value to mint");
        require(
            msg.sender == contract_owner || collectionWhitelists[collectionId].whitelist[msg.sender] > 0,
            "Only contract owner or whitelist can mint."
        );
        // Decrement remaining available mintables
        collections[collectionId].maxMintCount--;
        // Increment token count
        tokenCount++;
        _mint(msg.sender, tokenCount, 1, "New Mint");
        // Subtract from the number that can be minted from that address
        if(msg.sender != contract_owner) {
            collectionWhitelists[collectionId].whitelist[msg.sender]--;
        }
        // Set the ownership of this token to sender
        tokenToAddress[tokenCount] = msg.sender;
        // Push associated data for mint to NFT array
        passes.push(Pass({
                owner:  msg.sender,
                sale_price: msg.value
        }));
        // Split minting value
        uint artistFraction = 95;
        uint artistTotal = (collections[collectionId].cost * artistFraction) / 100;
        uint apTotal = msg.value - artistTotal;
        address artistAddress = collections[collectionId].artistPayableAddress;
        payable(contract_owner).transfer(artistTotal); // send the ETH to the artist
        payable(artistAddress).transfer(apTotal); // send the ETH to the Afterparty

        // Emit minted event
        emit PassMinted(contract_owner, msg.sender, msg.value);
    }



    /***********************************|
    |        Admin                      |
    |__________________________________*/

    // Examples:
    // Bored Ape1 = 0x426f726564204170653100000000000000000000000000000000000000000000
    // Bored Ape2 =  0x426f726564204170653200000000000000000000000000000000000000000000
    // Bored Ape3 =  0x426f726564204170653300000000000000000000000000000000000000000000
    // Afterparty All Access = 0x426f726564204170653100000000000000000000000000000000000000000000

    /**
     * @dev Create a collection of mint passes
     * @param name Name of the collection
     * @param collectionType Type of collection
     */
    function createCollection (bytes32 name, uint16 collectionType, uint256 cost, string memory url, uint256 maxMintCount, address artistPayableAddress) public {
        require(
            msg.sender == contract_owner,
            "Only contract owner can create collection."
        );
        collections.push(Collection({
            name: name,
            collectionType: collectionType,
            uri: url,
            cost: cost,
            maxMintCount: maxMintCount,
            artistPayableAddress: artistPayableAddress
        }));
        //uint256 collectionId = collections.length;
        collectionWhitelists.push();
    }

    function addToWhitelist ( address to, uint256 collectionId ) public  {
        require(
            msg.sender == contract_owner,
            "Only contract owner add to whitelist."
        );
        collectionWhitelists[collectionId].whitelist[to] = 1;
    }
    /**
     * @dev Function to enable/disable token minting
     * @param enabled The flag to turn minting on or off
     */
    function setEnabled(bool enabled) public {
        require(
            msg.sender == contract_owner,
            "Only contract owner add to whitelist."
        );
        _enabled = enabled;
    }

    /**
     * @dev Function to lock/unlock the on-chain metadata
     * @param locked The flag turn locked on
     */
    function setLocked(bool locked) public onlyUnlocked {
        require(
            msg.sender == contract_owner,
            "Only contract owner add to whitelist."
        );
        _locked = locked;
    }

    /**
     * @dev Function to update the base _uri for all tokens
     * @param newuri The base uri string
     */
    function setURI(string memory newuri) public  {
        require(
            msg.sender == contract_owner,
            "Only contract owner add to whitelist."
        );
        _setURI(newuri);
    }

    /***********************************|
    |    Utility Functions              |
    |__________________________________*/

    function mintedPassesCount() public view returns (uint256){
        return passes.length;
    }

    function ownerOf(uint256 idx) public view returns (address) {
        return tokenToAddress[idx];
    }



}
