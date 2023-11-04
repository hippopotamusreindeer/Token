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

// Define the contract, inheriting from multiple OpenZeppelin contracts for standard functionality.
contract Jerry is ERC20, ERC20Burnable, Ownable, ReentrancyGuard  {

    // State variables for weth and Uniswap router addresses, and developer wallet.
    address private immutable weth = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;
    address private immutable  developerWallet = 0x893a25A5744ab5680629D4EE8204B721B04342BD;
    address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    
    // Declare the Uniswap router.
    IUniswapV2Router02 private immutable uniswapRouter;

    // Initial token supply.
    uint256 private immutable initialSupply = 392491700000 ether;

    // Constants for burn and developer fees.
    uint8 private constant BURN_FEE = 1;    // 1% Burn-Fee
    uint8 private constant DEV_FEE = 15;    // 1.5% Dev-Fee
    
    // Modifier to check the deadline for transactions.
    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, "UniswapV2Router: EXPIRED");
        _;
    }



/*     // Setter functions
    // Function to set Developer Wallet address, only callable by the owner.
    function setDeveloperWallet(address developerWallet) external onlyOwner {
        require(_developerWallet != address(0), "Invalid Developer Wallet address");
        developerWallet = _developerWallet;
    }

    // Function to set weth address, only callable by the owner.
    function setWethAddress(address weth) external onlyOwner {
        require(_weth != address(0), "Invalid weth address");
        weth = _weth;
    } */



    // Constructor function for contract initialization.
    constructor(address initialOwner) public ERC20("Token", "TOKEN") Ownable(initialOwner) {
        _mint(msg.sender, initialSupply);
        uniswapRouter = IUniswapV2Router02(UNISWAP_V2_ROUTER);
    }

    //Fee Calculation
    // Internal function to calculate burning fee.
    function _calcBurningFee(uint256 amount) internal pure returns (uint256) {
        return amount * BURN_FEE / 100;
    }

    // Internal function to calculate developer fee.
    function _calcDevFee(uint256 amount) internal pure returns (uint256) {
        return amount * DEV_FEE / 1000;
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



    // Overriding ERC20 transfer to include custom fees.
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
    path[1] = weth; // Use the updated weth address

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
            block.timestamp
        );

        // Transfer Jerry Dev_Fees to developerWallet
        payable(developerWallet).transfer(devFeeAmount);

        // Burn the burn fee
        _burn(address(this), burnFeeAmount);
    }
}
