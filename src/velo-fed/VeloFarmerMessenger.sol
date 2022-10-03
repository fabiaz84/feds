pragma solidity ^0.8.13;

import "../interfaces/velo/ICrossDomainMessenger.sol";

contract VeloFarmerMessenger {
    ICrossDomainMessenger immutable crossDomainMessenger = ICrossDomainMessenger(0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1);
    address public veloFed;

    address public gov;
    address public chair;

    constructor(address gov_, address chair_, address veloFed_) {
        gov = gov_;
        chair = chair_;
        veloFed = veloFed_;
    } 

    modifier onlyGov {
        if (msg.sender != gov) revert OnlyGov();
        _;
    }

    modifier onlyChair {
        if (msg.sender != chair) revert OnlyChair();
        _;
    }

    error OnlyGov();
    error OnlyChair();

    //Helper functions

    function sendMessage(bytes memory message) internal {
        crossDomainMessenger.sendMessage(address(veloFed), message, 0);
    }

    //Gov Messaging functions

    function setMaxSlippageDolaToUsdc(uint newSlippage_) public onlyGov {
        sendMessage(abi.encodeWithSignature("setMaxSlippageDolaToUsdc(uint256)", newSlippage_));
    }

    function setMaxSlippageUsdcToDola(uint newSlippage_) public onlyGov {
        sendMessage(abi.encodeWithSignature("setMaxSlippageUsdcToDola(uint256)", newSlippage_));
    }

    function setMaxSlippageLiquidity(uint newSlippage_) public onlyGov {
        sendMessage(abi.encodeWithSignature("setMaxSlippageLiquidity(uint256)", newSlippage_));
    }

    function changeGov(address newGov_) public onlyGov {
        sendMessage(abi.encodeWithSignature("changeGov(address)", newGov_));
    }

    function changeTreasury(address newTreasury_) public onlyGov {
        sendMessage(abi.encodeWithSignature("changeTreasury(address)", newTreasury_));
    }

    function changeChair(address newChair_) public onlyGov {
        sendMessage(abi.encodeWithSignature("changeChair(address)", newChair_));
    }

    function changeL2Chair(address newChair_) public onlyGov {
        sendMessage(abi.encodeWithSignature("changeL2Chair(address)", newChair_));
    }

    function changeOptiFed(address optiFed_) public onlyGov {
        sendMessage(abi.encodeWithSignature("changeOptiFed(address)", optiFed_));
    }

    //Chair messaging functions

    function claimVeloRewards() public onlyChair {
        sendMessage(abi.encodeWithSignature("claimVeloRewards()"));
    }

    function claimRewards(address[] calldata addrs) public onlyChair {
        sendMessage(abi.encodeWithSignature("claimRewards(address)", addrs));
    }

    function swapAndDeposit(uint dolaAmount) public onlyChair {
        sendMessage(abi.encodeWithSignature("swapAndDeposit(uint256)", dolaAmount));
    }

    function deposit(uint dolaAmount, uint usdcAmount) public onlyChair {
        sendMessage(abi.encodeWithSignature("deposit(uint256,uint256)", dolaAmount, usdcAmount));
    }

    function withdrawLiquidity(uint dolaAmount) public onlyChair {
        sendMessage(abi.encodeWithSignature("withdrawLiquidity(uint256)", dolaAmount));
    }

    function withdrawLiquidityAndSwapToDola(uint dolaAmount) public onlyChair {
        sendMessage(abi.encodeWithSignature("withdrawLiquidityAndSwapToDOLA(uint256)", dolaAmount));
    }

    function withdrawToL1OptiFed(uint dolaAmount) public onlyChair {
        sendMessage(abi.encodeWithSignature("withdrawToL1OptiFed(uint256)", dolaAmount));
    }

    function withdrawToL1OptiFed(uint dolaAmount, uint usdcAmount) public onlyChair {
        sendMessage(abi.encodeWithSignature("withdrawToL1OptiFed(uint256,uint256)", dolaAmount, usdcAmount));
    }

    function withdrawTokensToL1(address l2Token, address to, uint amount) public onlyChair {
        sendMessage(abi.encodeWithSignature("withdrawTokensToL1(address,address,uint256)", l2Token, to, amount));
    }

    function swapUSDCtoDOLA(uint usdcAmount) public onlyChair {
        sendMessage(abi.encodeWithSignature("swapUSDCtoDOLA(uint256)", usdcAmount));
    }

    function swapDOLAtoUSDC(uint usdcAmount) public onlyChair {
        sendMessage(abi.encodeWithSignature("swapDOLAtoUSDC(uint256)", usdcAmount));
    }

    function resign() public onlyChair {
        sendMessage(abi.encodeWithSignature("resign()"));
    }

    //Gov functions

    function changeMessengerGov(address newGov_) public onlyGov {
        gov = newGov_;
    }

    function changeMessengerChair(address newChair_) public onlyChair {
        chair = newChair_;
    }
}