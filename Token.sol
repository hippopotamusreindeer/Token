// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// Importing various OpenZeppelin libraries and Uniswap interface.
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

// Token contract inheriting ERC20, ERC20Burnable, Ownable, and ReentrancyGuard
contract Token is ERC20, ERC20Burnable, Ownable, ReentrancyGuard  {
    // Initialize weth and Uniswap router addresses, and initial supply
    address private immutable weth;
    address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    // Constants for burn and developer fees
    uint8 private constant BURN_FEE = 1;    // 1% Burn-Fee
    uint8 private constant DEV_FEE = 15;    // 1.5% Dev-Fee
    address private immutable  developerWallet = 0x893a25A5744ab5680629D4EE8204B721B04342BD; //please insert address if necessary

    // Initial token supply
    uint256 private immutable initialSupply = 392491700000000000000000000000;

    // Declare the Uniswap router
    IUniswapV2Router02 private uniswapRouter;

    // Modifier to check transaction deadline
    uint private constant MAX_BLOCK_DIFFERENCE = 100;

    modifier ensure(uint targetBlock) {
        require(targetBlock >= block.number, "UniswapV2Router: EXPIRED");
        require(targetBlock <= block.number + MAX_BLOCK_DIFFERENCE, "UniswapV2Router: TOO FAR IN THE FUTURE");
        _;
    }

    // Constructor to initialize the contract
    constructor(address initialOwner, address _weth) public ERC20("Token", "TOKEN") Ownable(initialOwner) {
        _mint(msg.sender, initialSupply);
        uniswapRouter = IUniswapV2Router02(UNISWAP_V2_ROUTER);
        weth = _weth;
        //developerWallet = initialOwner;  // Initialize with the contract deployer address
    }


    // Internal function to calculate burning fee
    function _calcBurningFee(uint256 amount) internal pure returns (uint256) {
        return amount * BURN_FEE / 100;
    }

    // Internal function to calculate developer fee
    function _calcDevFee(uint256 amount) internal pure returns (uint256) {
        return amount * DEV_FEE / 1000;
    }

    // Internal function to calculate transfer amount after fees
    function _calcTransfer(uint256 amount, uint256 fee) internal pure returns (uint256) {
        require(amount >= fee, "Fee exceeds the transfer amount");
        return amount - fee;
    }

     // Internal function to handle fee calculation and return amount to be transferred
    function _handleFeesAndCalculateAmount(uint256 amountIn) internal returns (uint256) {
        uint256 localBurnFeeAmount = _calcBurningFee(amountIn);
        uint256 localDevFeeAmount = _calcDevFee(amountIn);
        
        // Transfer burn fee to developer wallet and burn it
        _transfer(msg.sender, developerWallet, localDevFeeAmount);
        _burn(msg.sender, localBurnFeeAmount);
        
        return amountIn - localBurnFeeAmount - localDevFeeAmount;
    }

    // Overridden transfer function to handle custom fees
    function _transfer(address sender, address recipient, uint256 amount) internal override {
        require(sender != address(0), "Transfer from the zero address");
        require(recipient != address(0), "Transfer to the zero address");

        if (sender != developerWallet && recipient != developerWallet) {
            uint256 burnFeeAmount = _calcBurningFee(amount);
            uint256 devFeeAmount = _calcDevFee(amount);

            uint256 transferAmount = _calcTransfer(amount, burnFeeAmount + devFeeAmount);

            super._transfer(sender, recipient, transferAmount);
            _burn(sender, burnFeeAmount);
            super._transfer(sender, developerWallet, devFeeAmount);
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
            path[1] = weth; // Use the updated weth address
        } else {
            path = new address[](3);
            path[0] = address(this);
            path[1] = weth; // Use the updated weth address
            path[2] = tokenOut;
        }

        // Perform the swap on Uniswap
        uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountToSwap,
            amountOutMin,
            path,
            to,
            block.number
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
    path[1] = weth; // Use the updated weth address

    // Perform the swap on Uniswap
    uniswapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
        amountToSwap,
        amountOutMin,
        path,
        to,
        block.number
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
        uint256 amountToSwap = msg.value - burnFeeAmount - devFeeAmount;

        // Prepare the token path for the swap (ETH -> weth -> Jerry)
        address[] memory path = new address[](2);
        path[0] = weth; // Use the updated weth address
        path[1] = address(this);

        // Perform the swap on Uniswap
        uniswapRouter.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amountToSwap}(
            amountOutMin,
            path,
            to,
            block.number
        );

        // Transfer Jerry Dev_Fees to developerWallet
        payable(developerWallet).transfer(devFeeAmount);

        // Burn the burn fee
        _burn(address(this), burnFeeAmount);
    }
}

