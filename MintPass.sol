// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.9.0;

// Afterparty MintPass allows buying a pass to acquite future collection pieces.


// Truffle imports
//import "../openzeppelin-contracts/contracts/token/ERC1155/presets/ERC1155PresetMinterPauser.sol";
//import "../openzeppelin-contracts/contracts/finance/PaymentSplitter.sol";
//import "../openzeppelin-contracts/contracts/utils/Counters.sol";

// Remix imports
import "@openzeppelin/contracts/token/ERC1155/presets/ERC1155PresetMinterPauser.sol";
import "@openzeppelin/contracts/finance/PaymentSplitter.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// Audits
// Last passed audits
// Mythrill: 2, 11/21/2021
// MythX:
// Audit Co:

contract MintPass is ERC1155PresetMinterPauser {

    /***********************************|
    |        Variables and Events       |
    |__________________________________*/
    uint16 public build = 4;
    uint256 public tokenCount = 0;
    uint16 public collectionCount = 0;

    // For Minting and Burning, locks the prices
    bool private _enabled = false;
    // For metadata (scripts), when locked, cannot be changed
    bool private _locked = false;


    /**
     * @dev Emitted when an original NFT with a new seed is minted
     */
    event CreateCollection(address indexed to, uint256 seed, uint256 indexed originalsMinted);
    event MintOriginal(address indexed to, uint256 seed, uint256 indexed originalsMinted);
    event NftBought(address _seller, address _buyer, uint256 _price);

    /**
     * @dev Emitted when an print is minted
     */
    event NftMinted(
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


    uint256 public constant TOKEN_TYPE_FT1 = 0;
    uint256 public constant TOKEN_TYPE_MINT_PASS = 1;
    uint256 public constant TOKEN_TYPE_AP_COL_1 = 2;

    bytes4 constant public ERC1155_ACCEPTED = 0xf23a6e61;


    address payable public contract_owner;
    mapping (uint256 => address) public creators;

    modifier ownerorWhitelistOnly() {
        require(contract_owner == msg.sender);
        _;
    }

    struct Nft {
        bytes32 name;   // short name (up to 32 bytes)
        address owner;
        uint sale_price;
    }

    struct Collection {
        bytes32 name;   // short name (up to 32 bytes)
        address owner;
        uint cost;
    }

    struct NftOwner {
        uint weight; // weight is accumulated by delegation
        bool voted;  // if true, that person already voted
        address delegate; // person delegated to
        uint num_minted;
        uint remaining_mint_count;
    }

    struct WhitelistAddresses {
        mapping(address => NftOwner) mint_whitelist;
    }


    mapping(uint256 => address) public tokenToAddress;
    mapping(address => NftOwner) public nftowners;
    //mapping(address => NftOwner) public mint_whitelist;

    Nft[] public nfts;
    Collection[] public collections;
    WhitelistAddresses[] public collectionWhitelists;

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
        require(msg.value >= collections[collectionId].cost, "Not enough value to mint");
        require(
            msg.sender == contract_owner || WhitelistAddresses[collectionId][msg.sender],
            "Only contract owner or whitelist can mint."
        );
        tokenCount++;
        _mint(msg.sender, tokenCount, 1, "New Mint");
        tokenToAddress[tokenCount] = msg.sender;
        nfts.push(Nft({
                name: "New Mint",
                owner:  msg.sender,
                sale_price: msg.value
        }));
        uint256 price = 500; //nfts[idx].sale_price;
        //require(price > 0, 'This token is not for sale');
        require(msg.value == price, 'Incorrect ether amount sent.');

        //address seller =  nfts[idx].owner;
        //nfts[idx].owner = msg.sender;
        //nfts[idx].sale_price = 0; // not for sale anymore
        payable(contract_owner).transfer(msg.value); // send the ETH to the seller

        emit NftBought(contract_owner, msg.sender, msg.value);
    }

    function ownerOf(uint256 idx) public view returns (address) {
        return tokenToAddress[idx];
    }



    /***********************************|
    |        Admin                      |
    |__________________________________*/

    // Examples:
    // Bored Ape1 = 0x426f726564204170653100000000000000000000000000000000000000000000
    // Bored Ape2 =  0x426f726564204170653200000000000000000000000000000000000000000000
    // Bored Ape3 =  0x426f726564204170653300000000000000000000000000000000000000000000

    /**
     * @dev Create a collection of mint passes
     * @param name Name of the collection
     * @param collectionType Type of collection
     */
    function createCollection (bytes32 name, uint16 collectionType, string memory url) public {
        require(
            msg.sender == contract_owner,
            "Only contract owner can create collection."
        );
        uint256 collectionId = collections.length;
        collections.push(Nft({
            name: name,
            collectionType: collectionType,
            uri: string
        }));
        WhitelistAddresses[collectionId] = [];
    }

    function addToWhitelist ( address to, uint256 collectionId ) public  {
        require(
            msg.sender == contract_owner,
            "Only contract owner add to whitelist."
        );
        WhitelistAddresses[collectionId][to].num_minted = 0;
        WhitelistAddresses[collectionId][to].remaining_mint_count = 1;

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
    |    Utility Internal Functions     |
    |__________________________________*/

    /**
    * @notice Convert uint256 to string
    * @param _i Unsigned integer to convert to string
    */
    function _uint2str(uint256 _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
        return "0";
        }

        uint256 j = _i;
        uint256 ii = _i;
        uint256 len;

        // Get number of bytes
        while (j != 0) {
        len++;
        j /= 10;
        }

        bytes memory bstr = new bytes(len);
        uint256 k = len - 1;

        // Get each individual ASCII
        while (ii != 0) {
            bstr[k--] = bytes(uint8(48 + ii % 10));
            ii /= 10;
        }

        // Convert to string
        return string(bstr);
    }

    function withdraw() public {
        require(
            msg.sender == contract_owner,
            "Only contract owner add to whitelist."
        );
        // get the amount of Ether stored in this contract
        uint amount = address(this).balance;

        // send all Ether to owner
        // Owner can receive Ether since the address of owner is payable
        (bool success, ) = contract_owner.call{value: amount}("");
        require(success, "Failed to send Ether");
    }

    function ap_allowBuy(uint256 idx, uint256 _price) external {
         require(
            msg.sender == nfts[idx].owner,
            "Not owner of this NFT"
        );
        require(_price > 0, 'Price zero');
        nfts[idx].sale_price = _price;
    }

    function ap_disallowBuy(uint256 idx) external {
         require(
            msg.sender == nfts[idx].owner,
            "Not owner of this NFT"
        );
        nfts[idx].sale_price = 0;
    }

    function ap_buy(uint256 idx) external payable {
        uint256 price = nfts[idx].sale_price;
        require(price > 0, 'This token is not for sale');
        require(msg.value == price, 'Incorrect value');

        address seller =  nfts[idx].owner;
        nfts[idx].owner = msg.sender;
        nfts[idx].sale_price = 0; // not for sale anymore
        payable(seller).transfer(msg.value); // send the ETH to the seller

        emit NftBought(seller, msg.sender, msg.value);
    }

    function ap_splitPayment(uint256 total, address seller) private  {
        uint256 seller_share = 10;

        payable(seller).transfer(seller_share); // send the ETH to the seller
        //payable(seller).transfer(house_percentage); // send the ETH to the seller
    }


}
