// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts@5.0.2/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts@5.0.2/access/Ownable.sol";
import "@openzeppelin/contracts@5.0.2/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts@5.0.2/token/ERC20/extensions/ERC20Burnable.sol";

contract PRX is ERC20, Pausable {
    address private _owner;
    address private _authorizedMinterBurner;
    mapping(address => bool) private _blacklist;
    uint256 public bridgeFee = 4 * 10 ** 18; // Example fee (4 PRX)
    uint256 public bridgeTotalFee;
    uint256 public fallbackCount;
    uint256 public receiveCount;
    mapping(uint256 => bool) public processedNonces;

    // Define the maximum total supply of the tokens
    uint256 public constant MAX_SUPPLY = 30000000 * 10 ** 18;
    uint256 public max_amount = 1000 * 10 ** 18;
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    modifier onlyAuthorized() {
        require(_msgSender() == _owner || _msgSender() == _authorizedMinterBurner, "Parex: caller is not authorized");
        _;
    }

    modifier notBlacklisted(address account) {
        require(!_blacklist[account], "Parex: account is blacklisted");
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function authorizedMinterBurner() public view returns (address) {
        return _authorizedMinterBurner;
    }

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;
    uint256 private _status  = NOT_ENTERED;
    error ReentrancyGuardReentrantCall();

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if (_status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        _status = ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == ENTERED;
    }


    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }
    event Burned(address indexed user, uint256 amount, uint256 date, uint256 nonce, uint256 targetChainID);
    event Minted(address indexed user, uint256 amount, uint256 date, uint256 nonce);

    constructor(address initialOwner, address initialAuthorized) ERC20("PAREX", "PRX") {
        _owner = initialOwner;
        _authorizedMinterBurner = initialAuthorized;
        // Mint 7,000,000 tokens to the creator
        _mint(msg.sender, 7000000 * 10 ** 18);
    }

    function setAuthorizedMinterBurner(address newAuthorized) public onlyOwner {
        _authorizedMinterBurner = newAuthorized;
    }

    function mint(address to, uint256 amount) public onlyAuthorized notBlacklisted(to) {
        // Check that the new total supply will not exceed the maximum supply
        require(totalSupply() + amount <= MAX_SUPPLY, "Parex: max total supply exceeded");
        _mint(to, amount);
    }

    function burn(address account, uint256 amount) public onlyAuthorized notBlacklisted(account) {
        _burn(account, amount);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function blacklist(address account) public onlyAuthorized nonReentrant {
        _blacklist[account] = true;
    }

    function unblacklist(address account) public onlyAuthorized nonReentrant {
        _blacklist[account] = false;
    }

    function isBlacklisted(address account) public view returns (bool) {
        return _blacklist[account];
    }

    // Override _transfer, _mint, and _burn to respect pause state and blacklist
    function _transfer(address from, address to, uint256 amount) internal virtual override whenNotPaused notBlacklisted(from) notBlacklisted(to) nonReentrant {
        super._transfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal virtual override whenNotPaused notBlacklisted(account) nonReentrant {
        super._mint(account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual override whenNotPaused notBlacklisted(account) nonReentrant {
        super._burn(account, amount);
    }

    function lockTokens(uint256 amount, uint256 nonce, uint256 targetChainID) external  whenNotPaused   {
        require(!processedNonces[nonce], "Transfer already processed");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance to lock tokens");
        require(max_amount >= amount, "Lock amount exceeds maximum allowed");
        // Burn tokens from the user's balance using burnFrom
        super._burn(msg.sender,amount);

        processedNonces[nonce] = true;
        emit Burned(msg.sender, amount, block.timestamp, nonce, targetChainID);
    }

    function unlockTokens(address to, uint256 amount, uint256 nonce) external onlyAuthorized {
        require(!processedNonces[nonce], "Transfer already processed");
        processedNonces[nonce] = true;
        uint256 amountToMint = amount;

        if (amount > 0) {
            require(amount > bridgeFee, "Amount must be greater than bridge fee");
            amountToMint -= bridgeFee; // Deduct the bridge fee
            bridgeTotalFee += bridgeFee; // Accumulate the total fees collected
        }

        mint(to, amountToMint); // Mint tokens to the recipient
        emit Minted(to, amountToMint, block.timestamp, nonce);
    }

    function setBridgeFee(uint256 _fee) public onlyAuthorized {
        require(_fee > 0, "Bridge fee must be greater than 0");
        bridgeFee = _fee;
    }

    function setMaxAmount(uint256 max) public onlyAuthorized {
        require(max > 0, "Max Amount");
        max_amount = max;
    }

    function sendBridgeOwnerReward() public onlyAuthorized {
        if (bridgeTotalFee > 0) {
            address payable bridgeOwner = payable(owner());
            require(transfer(bridgeOwner, bridgeTotalFee), "Transfer failed");
            bridgeTotalFee = 0; // Reset the total fee counter after transferring
        }
    }    
}