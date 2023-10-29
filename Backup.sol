// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// Importing various OpenZeppelin libraries and Uniswap interface.
import "../node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "../node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "../node_modules/@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "../node_modules/@openzeppelin/contracts/security/ReentrancyGuard.sol";

import '@uniswap/lib/contracts/libraries/TransferHelper.sol';

// Token contract inheriting ERC20, ERC20Burnable, Ownable, and ReentrancyGuard
contract Token is ERC20, ERC20Burnable, Ownable, ReentrancyGuard  {

    // Initialize weth and Uniswap router addresses, and initial supply
    address private immutable weth = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;
    address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private immutable  developerWallet = 0x893a25A5744ab5680629D4EE8204B721B04342BD; 
    // Constants for burn and developer fees
    uint8 private constant BURN_FEE = 1;    // 1% Burn-Fee
    uint8 private constant DEV_FEE = 15;    // 1.5% Dev-Fee
    // Initial token supply
    uint256 private immutable initialSupply = 392491700000 * 10**18;
    // Declare the Uniswap router
    IUniswapV2Router02 private immutable uniswapRouter;
    
    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, "UniswapV2Router: EXPIRED");
        _;
    }

    // Constructor to initialize the contract
    constructor(address initialOwner, address _weth) public ERC20("Token", "TOKEN") Ownable(initialOwner) {
        require(initialOwner != address(0), "Invalid owner address");
        require(_weth != address(0), "Invalid WETH address");
        _mint(msg.sender, initialSupply);
        uniswapRouter = IUniswapV2Router02(UNISWAP_V2_ROUTER);
        weth = _weth;
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

    // Overridden transfer function to handle custom fees
    function _transfer(address sender, address recipient, uint256 amount) internal override {
        require(sender != address(0), "Transfer from the zero address"); //Sender darf nicht Null_Adresse sein
        require(recipient != address(0), "Transfer to the zero address");  //Empfänger darf nicht Null_Adresse sein    
        if (sender != developerWallet && recipient != developerWallet) { //Prüfen das der Sender bzw. der Empfänger nicht die Entwicklerwallet sind
            uint256 burnFeeAmount = _calcBurningFee(amount); //Berechnen des BurningFee
            uint256 devFeeAmount = _calcDevFee(amount); //Berechnen des DevFee
            uint256 transferAmount = _calcTransfer(amount, burnFeeAmount + devFeeAmount); //TransferAmount abzüglich der Gebühren
            _burn(sender, burnFeeAmount); //Bunren des BurnfeeAmoutn
            super._transfer(sender, recipient, transferAmount); //dem Swapper den Amount der Token abzüglich Gebühren überweisen
            super._transfer(sender, developerWallet, devFeeAmount); //DevFees an die DevWallet schicken
        } else { 
            super._transfer(sender, recipient, amount); //Wenn Sender oder Empfäner DevWallet --> Transfer ohne Gebühren
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
        require(to != address(0), "Invalid recipient address"); // Added this line
        require(amountIn > 0, "Amount must be greater than 0");

        // Read the storage variable once into a local variable
        address localWeth = weth;

        // Calculate the fees
        uint256 burnFeeAmount = _calcBurningFee(amountIn);
        uint256 devFeeAmount = _calcDevFee(amountIn);
        // Calculate the amount to swap after deducting fees
        uint256 amountToSwap = amountIn - burnFeeAmount - devFeeAmount;

        // Transfer und Gebührenanwendung
        _transfer(msg.sender, address(this), amountIn);

        // Approve the Uniswap router to spend JERRY tokens
        _approve(address(this), UNISWAP_V2_ROUTER, amountToSwap);

        // Prepare the token path for the swap
        address[] memory path;
        if (tokenOut == localWeth) {
            path = new address[](2);
            path[0] = address(this);
            path[1] = localWeth; // Use the local weth variable
        } else {
            path = new address[](3);
            path[0] = address(this);
            path[1] = localWeth; // Use the local weth variable
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
    //Probleme in der Funktion
    // Swap Jerry tokens for ETH using Uniswap
    function swapJerryForETH(
        uint256 amountIn, 
        uint256 amountOutMin, 
        address to, 
        uint256 deadline
    ) external ensure(deadline) nonReentrant {
        require(amountIn > 0, "Amount must be greater than 0");
        require(to != address(0), "Invalid recipient address");

        // Calculate the fees
        uint256 burnFeeAmount = _calcBurningFee(amountIn);
        uint256 devFeeAmount = _calcDevFee(amountIn);
        // Calculate the amount to swap after deducting fees
        uint256 amountToSwap = amountIn - burnFeeAmount - devFeeAmount;
        
        // Approve Uniswap to spend tokens (assuming uniswapRouter is an instance of IUniswapV2Router02)
        approve(address(uniswapRouter), amountToSwap);

        // Transfer und Gebührenanwendung
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

//!!MUSS NOCH ÜBERARBEITET WERDEN!!
// Swap ETH for Jerry tokens using Uniswap
function swapETHForJerry(
    uint256 amountOutMin, 
    address to, 
    uint256 deadline
) external payable ensure(deadline) nonReentrant {
    require(msg.value > 0, "Amount must be greater than 0");
    require(to != address(0), "Invalid recipient address");

    // Prepare the token path for the swap (ETH -> weth -> Jerry)
    address[] memory path = new address[](2);
    path[0] = weth;
    path[1] = address(this);

    // Perform the swap on Uniswap
    uint[] memory amounts = uniswapRouter.swapExactETHForTokens{value: msg.value}(
        amountOutMin,
        path,
        address(this),  // Empfänger ist erstmal der Smart Contract selbst
        block.timestamp 
    );

    // Jetzt haben wir Jerry Tokens, basierend darauf können wir die Gebühren berechnen
    uint256 totalReceivedJerry = amounts[1];
    uint256 burnFeeAmount = _calcBurningFee(totalReceivedJerry);
    uint256 devFeeAmount = _calcDevFee(totalReceivedJerry);

    // Berechne den Betrag, der nach Abzug der Gebühren übrig bleibt
    uint256 amountToTransfer = totalReceivedJerry - burnFeeAmount - devFeeAmount;

    // Überweise die verbleibenden Jerry Tokens an den Empfänger
    _transfer(address(this), to, amountToTransfer);

}
}

