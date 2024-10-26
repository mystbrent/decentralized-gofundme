import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Lockup, LockupLinear } from "./DataTypes.sol";


interface ISablierV2LockupLinear {
    struct CreateWithDurations {
        address sender;
        address recipient;
        uint128 totalAmount;
        IERC20 asset;
        bool cancelable;
        bool transferable;
        Durations durations;
        Broker broker;
    }

    struct Durations {
        uint40 cliff;
        uint40 total;
    }

    struct Broker {
        address account;
        uint256 fee;
    }

    function createWithDurations(CreateWithDurations calldata params) external returns (uint256 streamId);
    function getStream(uint256 streamId) external view returns (LockupLinear.StreamLL memory stream);
    function cancelStream(uint256 streamId) external returns (uint256 senderAmount, uint256 recipientAmount);
}