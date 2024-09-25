
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts@5.0.2/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts@5.0.2/access/Ownable.sol";
import "@openzeppelin/contracts@5.0.2/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts@5.0.2/token/ERC20/extensions/ERC20Burnable.sol";



contract PRX is ERC20, Pausable {
    address private _owner;
    mapping(address => bool) private _blacklist;
    // Define the maximum total supply of the tokens
    uint256 public constant MAX_SUPPLY = 30000000 * 10 ** 18;
    uint256 public constant maxBridgeFee = 100  * 10 ** 18; // Max fee (100 PRX)
    // Define a mapping to keep track of the number of times a nonce has been processed
    uint256 public bridgeTotalFee;
    uint256 public fallbackCount;
    uint256 public receiveCount;
    mapping(uint256 => bool) public processedNonces;
    uint256 public bridgeFee = 4 * 10 ** 18; //  fee (4 PRX)
    uint256 public maxAmount = 100000 * 10 ** 18; // for one tx max Amount



    address[] public signers; // List of signers
    mapping(address => bool) public isSigner; // To verify signers
    mapping(address => bool) public hasApproved; // To track approvals
    uint256 public requiredApprovals; // Number of required approvals
    uint256 public approvalCount; // Counter for approvals




    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function _burnFrom(address account, uint256 amount) internal  virtual  {
        uint256 currentAllowance = allowance(account, address(this));
        require(currentAllowance >= amount, "ERC20: burn amount exceeds allowance");
        _burn(account, amount);
    }

    modifier notBlacklisted(address account) {
        require(!_blacklist[account], "Parex: account is blacklisted");
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
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

    constructor(address initialOwner, address[] memory _signers, uint256 _requiredApprovals) ERC20("PAREX", "PRX") {
        require(initialOwner != address(0), "Invalid address: zero address provided");
        _owner = initialOwner;
        require(_signers.length >= _requiredApprovals, "Not enough signers for required approvals");
        signers = _signers;
        requiredApprovals = _requiredApprovals;
        for (uint256 i = 0; i < _signers.length; i++) {
            isSigner[_signers[i]] = true;
        }
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function blacklist(address account) public onlyOwner nonReentrant {
        _blacklist[account] = true;
    }

    function unblacklist(address account) public onlyOwner nonReentrant {
        _blacklist[account] = false;
    }

    function isBlacklisted(address account) public view returns (bool) {
        return _blacklist[account];
    }


    function _mint(address account, uint256 amount) internal virtual override whenNotPaused notBlacklisted(account)  {
        require(totalSupply() + amount <= MAX_SUPPLY, "Parex: max total supply exceeded");
        super._mint(account, amount);
    }

    function lockTokens(uint256 amount, uint256 nonce, uint256 targetChainID) external  whenNotPaused   {
        require(!processedNonces[nonce], "Transfer already processed");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance to lock tokens");
        require(maxAmount >= amount, "Lock amount exceeds maximum allowed");

        // Burn tokens from the user's balance using burnFrom
        _burnFrom(msg.sender,amount);

        processedNonces[nonce] = true;
        emit Burned(msg.sender, amount, block.timestamp, nonce, targetChainID);
    }

    function unlockTokens(address to, uint256 amount, uint256 nonce) external onlyOwner nonReentrant {
        require(!processedNonces[nonce], "Transfer already processed");
        processedNonces[nonce] = true;
        uint256 amountToMint = amount;

        require(amount > 0, "Amount must be greater than 0");
        require(amount > bridgeFee, "Amount must be greater than bridge fee");
        amountToMint -= bridgeFee; // Deduct the bridge fee
        bridgeTotalFee += bridgeFee; // Accumulate the total fees collected
      

        _mint(to, amountToMint); // Mint tokens to the recipient
        emit Minted(to, amountToMint, block.timestamp, nonce);
    }

    function setBridgeFee(uint256 _fee) public onlyOwner {
        require(_fee > 0, "Bridge fee must be greater than 0");
        require(_fee < maxBridgeFee, "Bridge fee must 100 PRX");
        
        bridgeFee = _fee;
    }

    function setMaxAmount(uint256 max) public onlyOwner {
        require(max > 0, "Max Amount must be greater than 0");
        maxAmount = max;
       
    }
    


    function approveBridgeReward() external {
        require(isSigner[msg.sender], "Only signers can approve");
        require(!hasApproved[msg.sender], "Signer has already approved");
        hasApproved[msg.sender] = true;
        approvalCount++;
    }

    function resetApprovals() internal {
        for (uint256 i = 0; i < signers.length; i++) {
            hasApproved[signers[i]] = false;
        }
        approvalCount = 0;
    }

    function sendBridgeOwnerReward() public onlyOwner {
        require(approvalCount >= requiredApprovals, "Not enough approvals");
        require(address(this).balance >= bridgeTotalFee, "Insufficient balance");
        if (bridgeTotalFee > 0) {
            address payable bridgeOwner = payable(owner());
            (bool success, ) = bridgeOwner.call{value: bridgeTotalFee}("");
            require(success, "Transfer failed");
            bridgeTotalFee = 0;
        }
        resetApprovals();
    }



}




