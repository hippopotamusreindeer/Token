// SPDX-License-Identifier: MIT
// Specifying the license under which the code is available.
pragma solidity ^0.8.20;
// Using a fixed version of Solidity.

pragma abicoder v2;
// Enabling ABI v2 encoding, which allows passing structs as function arguments.

// Importing various OpenZeppelin libraries and Uniswap interface.
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// Define the contract, inheriting from multiple OpenZeppelin contracts for standard functionality
contract JERRY is ERC20, ERC20Burnable, Ownable, ReentrancyGuard  {

    // State variables for weth and Uniswap router addresses, and developer wallet
    address private immutable weth = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;
    address private immutable  developerWallet = 0x893a25A5744ab5680629D4EE8204B721B04342BD;
    address private immutable  cexWallet = 0xbBAb880C4028aF3187Fe507923ce92449A48307f; //Ändern !!
    address private immutable  marketingWallet = 0x9F00c648E1Bb9488979D8D97A4D4dfc6Bc7fc084; //Ändern!!
    address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private pairAddressUniswap;

    // Declare the Uniswap router.
    IUniswapV2Router02 private immutable uniswapRouter;

    // Initial token supply.
    uint256 private immutable initialSupply = 392491700000 ether;
    uint256 public _maxWltSize;
    uint256 public _maxWltSizePercentage = 3;

    // Constants for burn and developer fees.
    uint8 private constant BURN_FEE = 1;    // 1% Burn-Fee
    uint8 private constant DEV_FEE = 19;    // 1.9% Dev-Fee
    uint8 private constant DIVIDE_BY_HUNDRED = 100;
    uint16 private constant DIVIDE_BY_THOUSAND = 1000;

    // Modifier to check the deadline for transactions.
    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, "UniswapV2Router: EXPIRED");
        _;
    }

    // Constructor function for contract initialization.
    constructor(address initialOwner) public ERC20("Jerry", "JERRY") Ownable(initialOwner) {
        _mint(msg.sender, initialSupply);
        uniswapRouter = IUniswapV2Router02(UNISWAP_V2_ROUTER);
        _maxWltSize = (totalSupply() * _maxWltSizePercentage) / 100;
    }

    function pairAddress(address _pairAddress) external onlyOwner nonReentrant{
        require(_pairAddress != address(0), "Invalid Developer Wallet address");
        pairAddressUniswap = _pairAddress;
    }

    //Fee Calculation
    // Internal function to calculate burning fee.
    function _calcBurningFee(uint256 amount) internal pure returns (uint256) {
        return amount * BURN_FEE / DIVIDE_BY_HUNDRED;
    }

    // Internal function to calculate developer fee.
    function _calcDevFee(uint256 amount) internal pure returns (uint256) {
        return amount * DEV_FEE / DIVIDE_BY_THOUSAND;
    }

    // Internal function to calculate transfer amount after fees.
    function _calcTransfer(uint256 amount, uint256 fee) internal pure returns (uint256) {
        require(amount >= fee, "Fee exceeds the transfer amount");
        return amount - fee;
    }

     // Internal function to handle fee calculation and return amount to be transferred.
    function _handleFeesAndCalculateAmount(uint256 amountIn) internal returns (uint256) {
        uint256 localBurnFeeAmount = _calcBurningFee(amountIn);
        uint256 localDevFeeAmount = _calcDevFee(amountIn);
        
        // Transfer burn fee to developer wallet and burn it.
        _transfer(msg.sender, developerWallet, localBurnFeeAmount);
        _burn(msg.sender, localBurnFeeAmount);
        
        return amountIn - localBurnFeeAmount - localDevFeeAmount;
    }

   // Overriding ERC20 transfer to include custom fees and check for max wallet size.
    function _transfer(address sender, address recipient, uint256 amount) internal override {
        require(sender != address(0), "Transfer from the zero address");
        require(recipient != address(0), "Transfer to the zero address");

        // maximum WalletSize of 3%
        uint256 maxWalletSize = totalSupply() * _maxWltSizePercentage / DIVIDE_BY_HUNDRED;

        // Check if transfer would bypass the maximum WalletSize of the receiver
        if (recipient != pairAddressUniswap && recipient != developerWallet && sender != developerWallet) {
            require(balanceOf(recipient) + amount <= maxWalletSize, "Transfer would exceed maximum wallet balance");
        }

          if (sender != developerWallet && recipient != developerWallet) {
        // Calaculate Fees
        uint256 burnFeeAmount = _calcBurningFee(amount);
        uint256 devFeeAmount = _calcDevFee(amount);
        uint256 transferAmount = _calcTransfer(amount, burnFeeAmount + devFeeAmount);

        super._transfer(sender, recipient, transferAmount);
        if (burnFeeAmount > 0) {
            _burn(sender, burnFeeAmount);
        }
        if (devFeeAmount > 0) {
            super._transfer(sender, developerWallet, devFeeAmount);
        }
        } else {
            super._transfer(sender, recipient, amount);
        }
    }

    // Swap Jerry tokens for another ERC20 token using Uniswap
    function swapTokensForToken(
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) nonReentrant {
        require(tokenOut != address(0), "Invalid token address");
        require(tokenOut != address(this), "Cannot swap to the same token");
        require(amountIn > 0, "Amount must be greater than 0");
    
        // Calculate the amount to swap after deducting fees
        uint256 amountToSwap = _handleFeesAndCalculateAmount(amountIn);

        // Transfer Jerry tokens from the sender to this contract
        _transfer(msg.sender, address(this), amountIn);

        // Approve the Uniswap router to spend JERRY tokens
        _approve(address(this), UNISWAP_V2_ROUTER, amountToSwap);

        // Prepare the token path for the swap
        address[] memory path;
        if (tokenOut == weth) {
            path = new address[](2);
            path[0] = address(this);
            path[1] = weth; 
        } else {
            path = new address[](3);
            path[0] = address(this);
            path[1] = weth; 
            path[2] = tokenOut;
        }

        // Perform the swap on Uniswap
        uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountToSwap,
            amountOutMin,
            path,
            to,
            block.timestamp
        );
    }

    // Swap Jerry tokens for ETH using Uniswap
    function swapJerryForETH(
        uint256 amountIn, 
        uint256 amountOutMin, 
        address to, 
        uint256 deadline
        ) external ensure(deadline) nonReentrant {
    require(amountIn > 0, "Amount must be greater than 0");

    // Approve the Uniswap router to spend JERRY tokens
    _approve(address(this), UNISWAP_V2_ROUTER, amountIn);

    uint256 amountToSwap = _handleFeesAndCalculateAmount(amountIn);

    // Transfer Jerry tokens from the sender to this contract
    _transfer(msg.sender, address(this), amountIn);

    // Prepare the token path for the swap (Jerry -> weth -> ETH)
    address[] memory path = new address[](2);
    path[0] = address(this);
    path[1] = weth; 

    // Perform the swap on Uniswap
    uniswapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
        amountToSwap,
        amountOutMin,
        path,
        to,
        block.timestamp
    );
}

    // Swap ETH for Jerry tokens using Uniswap
    function swapETHForJerry(
        uint256 amountOutMin, 
        address to, 
        uint256 deadline
        ) external payable ensure(deadline) nonReentrant {
        require(msg.value > 0, "Amount must be greater than 0");

        // Calculate the fees
        uint256 burnFeeAmount = _calcBurningFee(msg.value);
        uint256 devFeeAmount = _calcDevFee(msg.value);

        // Calculate the amount to swap after deducting fees
        uint amountToSwap = msg.value - burnFeeAmount - devFeeAmount;
        // Prepare the token path for the swap (ETH -> weth -> Jerry)
        address[] memory path = new address[](2);
        path[0] = weth; 
        path[1] = address(this);

        // Perform the swap on Uniswap
        uniswapRouter.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amountToSwap}(
            amountOutMin,
            path,
            to,
            block.timestamp
        );

        // Transfer Jerry Dev_Fees to developerWallet
        payable(developerWallet).transfer(devFeeAmount);

        // Burn the burn fee
        _burn(address(this), burnFeeAmount);
    }
}
