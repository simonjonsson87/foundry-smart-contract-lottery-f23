// SPDX-License-:MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Raffle} from "src/Raffle.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is Test {
    Raffle public raffle;
    HelperConfig public helperConfig;

    uint256 public constant PLAYER_STARTING_BALANCE = 10 ether;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint32 callbackGasLimit;
    uint256 subscriptionId;

    address public PLAYER1 = makeAddr("player");
    address public PLAYER2 = makeAddr("player2");

    function setUp() public {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();

        HelperConfig.NetworkConfig memory config = helperConfig.getConfigByChainId(block.chainid);

        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        callbackGasLimit = config.callbackGasLimit;
        subscriptionId = config.subscriptionId;

        vm.deal(PLAYER1, PLAYER_STARTING_BALANCE);
        vm.deal(PLAYER2, PLAYER_STARTING_BALANCE);
    }

    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER1);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    /////////////////////////////////////////////////////////////////////////
    // General tests
    /////////////////////////////////////////////////////////////////////////
    function testRaffleInitialisesToOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    /////////////////////////////////////////////////////////////////////////
    // Tests for function enterRaffle
    /////////////////////////////////////////////////////////////////////////
    function testEnterRaffleRevertIfNotEnoughEthSent() public {
        vm.prank(PLAYER1);
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle{value: entranceFee - 1}();
    }

    function testEnterRaffleRevertIfRaffleNotOpen() public raffleEnteredAndTimePassed {
        // Arrange
        raffle.performUpkeep("");
        // Act / Assess
        vm.prank(PLAYER2);
        vm.expectRevert(Raffle.Raffle__NotOpen.selector);
        raffle.enterRaffle{value: entranceFee}();
    }
    /////////////////////////////////////////////////////////////////////////
    // Tests for function checkUpkeep()
    /////////////////////////////////////////////////////////////////////////

    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleIsntOpen() public raffleEnteredAndTimePassed {
        // Arrange
        raffle.performUpkeep("");
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        // Assert
        assert(raffleState == Raffle.RaffleState.CALCULATING);
        assert(upkeepNeeded == false);
    }

    function testCheckUpkeepReturnsFalseIfTimeNotPassed() public {
        // Arrange
        vm.prank(PLAYER1);
        raffle.enterRaffle{value: entranceFee}();
        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        // Assert
        assert(!upkeepNeeded);
        require(
            block.timestamp - raffle.getLastTimestamp() < interval,
            "This situation should never be able to happen if the test works as expected."
        );
    }

    function testCheckUpkeepReturnsTrue() public raffleEnteredAndTimePassed {
        // Arrange
        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        // Assert
        assert(upkeepNeeded);
    }

    /////////////////////////////////////////////////////////////////////////
    // Tests for function performUpkeep()
    /////////////////////////////////////////////////////////////////////////
    function testPerformUpkeepSetsRaffleStatusToCalculating() public raffleEnteredAndTimePassed {
        // Arrange
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        require(upkeepNeeded, "Something is wrong with this test, because upkeep should be needed now");
        // Act
        raffle.performUpkeep("");
        //
        assert(raffle.getRaffleState() == Raffle.RaffleState.CALCULATING);
    }

    function testPerformUpkeepRevertIfRaffleNotOpen() public raffleEnteredAndTimePassed {
        // Arrange
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        require(upkeepNeeded, "Something is wrong with this test, because upkeep should be needed now");
        raffle.performUpkeep("");
        assert(raffle.getRaffleState() == Raffle.RaffleState.CALCULATING);
        // Act / Assert
        vm.expectRevert(Raffle.Raffle__NotOpen.selector);
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertIfIntervalNotPassed() public {
        // Arrange
        vm.prank(PLAYER1);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval - 1);
        vm.roll(block.number + 1);
        // Act / Assert
        vm.expectRevert();
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertIfNoPlayers() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        // Act / Assert
        bytes memory expectedError = abi.encodeWithSelector(
            Raffle.Raffle__UpkeepNotNeeded.selector,
            0, // expected balance
            0, // expected playersLength
            uint256(Raffle.RaffleState.OPEN) // expected raffle state
        );
        vm.expectRevert(expectedError);
        raffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEnteredAndTimePassed {
        // Act
        vm.recordLogs();
        raffle.performUpkeep(""); // emits requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        // Assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        // requestId = raffle.getLastRequestId();
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1); // 0 = open, 1 = calculating
    }

    /////////////////////////////////////////////////////////////////////////
    // fulfillRandomWords()
    /////////////////////////////////////////////////////////////////////////
    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId)
        public
        raffleEnteredAndTimePassed
    {
        // Arrange
        // Act / Assert
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        // vm.mockCall could be used here...
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEnteredAndTimePassed {
        // Arrange

        uint256 additionalEntrants = 3;
        uint256 startingIndex = 1;

        for (uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++) {
            address player = address(uint160(i));
            hoax(player, 1 ether);
            raffle.enterRaffle{value: entranceFee}();
        }

        vm.recordLogs();
        raffle.performUpkeep(""); // emits requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        // Pretend to be Chainlink VRF
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));
    }

}
