pragma solidity ^0.8.0;

interface Iconf {
    function senator() external view returns (address);

    function poc() external view returns (address);

    function stEpoch() external view returns (uint);

    function voteEpoch() external view returns (uint);

    function senatorNum() external view returns (uint);

    function offLine() external view returns (uint);

    function executEpoch() external view returns (uint);
}

interface Ipoc {
    function updateExecuter() external;
}

interface Isenator {
    function epochId() external view returns (uint);

    function executerId() external view returns (uint);

    function executerIndate() external view returns (uint);

    function getExecuter() external view returns (address);

    function isSenator(address) external view returns (bool);

    function updateExecuter() external;
}

contract Initialize {
    bool internal initialized;

    modifier init() {
        require(!initialized, "initialized");
        _;
        initialized = true;
    }
}

contract snapshoot is Initialize {
    address public conf;

    snapshootProposal[] internal snapshoots;

    enum Result {
        PENDING,
        SUCCESS,
        FAILED
    }

    struct snapshootProposal {
        uint epochId;
        uint executerId;
        string prHash;
        string prId;
        address proposer;
        uint proposalTime;
        address[] assentors;
        address[] unAssentors;
        Result result;
    }

    event SendSnapshootProposal(
        uint indexed executerId,
        address executer,
        string prHash,
        string prId
    );

    modifier onlyExecuter() {
        require(
            Isenator(Iconf(conf).senator()).getExecuter() == msg.sender,
            "access denied: only Executer"
        );
        _;
    }

    modifier onlySenator() {
        require(
            Isenator(Iconf(conf).senator()).isSenator(msg.sender),
            "access denied: only senator"
        );
        _;
    }

    modifier onlyPoc() {
        require(Iconf(conf).poc() == msg.sender, "access denied: only poc");
        _;
    }

    function initialize(address _conf) external init {
        conf = _conf;
    }

    function totalSnapshoots() public view returns (uint256) {
        return snapshoots.length;
    }

    function snapshootVoteDetails(
        uint256 id
    )
        public
        view
        returns (address[] memory assentors, address[] memory unassentors)
    {
        return (snapshoots[id].assentors, snapshoots[id].unAssentors);
    }

    function sendSnapshootProposal(
        string memory _prHash,
        string memory _prId
    ) external onlyExecuter {
        if (snapshoots.length != 0)
            require(
                snapshoots[snapshoots.length - 1].proposer != msg.sender,
                "resubmit"
            );

        uint _epochId = Isenator(Iconf(conf).senator()).epochId();
        uint _executerId = Isenator(Iconf(conf).senator()).executerId();
        address[] memory nilArray;
        snapshoots.push(
            snapshootProposal(
                _epochId,
                _executerId,
                _prHash,
                _prId,
                msg.sender,
                block.timestamp,
                nilArray,
                nilArray,
                Result.PENDING
            )
        );
        snapshoots[snapshoots.length - 1].assentors.push(msg.sender);

        emit SendSnapshootProposal(_executerId, msg.sender, _prHash, _prId);
    }

    function latestSnapshootProposal()
        external
        view
        returns (
            uint epochId,
            uint executerId,
            string memory prHash,
            string memory prId,
            address proposer,
            uint proposalTime,
            uint result
        )
    {
        snapshootProposal memory sp = snapshoots[snapshoots.length - 1];
        return (
            sp.epochId,
            sp.executerId,
            sp.prHash,
            sp.prId,
            sp.proposer,
            sp.proposalTime,
            uint(sp.result)
        );
    }

    function latestSuccesSnapshootProposal()
        external
        view
        returns (
            uint epochId,
            uint executerId,
            string memory prHash,
            string memory prId,
            address proposer,
            uint proposalTime,
            uint result
        )
    {
        snapshootProposal memory sp;
        for (uint i = snapshoots.length - 1; i >= 0; i--) {
            if (snapshoots[i].result == Result.SUCCESS) {
                sp = snapshoots[i];
                break;
            }
        }
        return (
            sp.epochId,
            sp.executerId,
            sp.prHash,
            sp.prId,
            sp.proposer,
            sp.proposalTime,
            uint(sp.result)
        );
    }

    function vote(bool v) external onlySenator {
        require(snapshoots.length != 0, "No snapshootProposal");
        require(!isResolution(), "Reached a consensus");

        for (
            uint i = 0;
            i < snapshoots[snapshoots.length - 1].assentors.length;
            i++
        ) {
            require(
                snapshoots[snapshoots.length - 1].assentors[i] != msg.sender,
                "multiple voting"
            );
        }
        for (
            uint i = 0;
            i < snapshoots[snapshoots.length - 1].unAssentors.length;
            i++
        ) {
            require(
                snapshoots[snapshoots.length - 1].unAssentors[i] != msg.sender,
                "multiple voting"
            );
        }

        if (v) {
            snapshoots[snapshoots.length - 1].assentors.push(msg.sender);
            if (
                snapshoots[snapshoots.length - 1].assentors.length >=
                Iconf(conf).offLine()
            ) snapshoots[snapshoots.length - 1].result = Result.SUCCESS;
        } else {
            snapshoots[snapshoots.length - 1].unAssentors.push(msg.sender);

            if (
                snapshoots[snapshoots.length - 1].unAssentors.length >
                Iconf(conf).senatorNum() - Iconf(conf).offLine()
            ) {
                snapshoots[snapshoots.length - 1].result = Result.FAILED;
                //Ipoc(Iconf(conf).poc()).updateExecuter();
                Isenator(Iconf(conf).senator()).updateExecuter();
            }
        }
    }

    function veto() external onlyPoc {
        if (snapshoots.length != 0)
            snapshoots[snapshoots.length - 1].result = Result.FAILED;
    }

    function isResolution() public view returns (bool) {
        if (
            snapshoots.length == 0 ||
            snapshoots[snapshoots.length - 1].result != Result.PENDING
        ) {
            return true;
        } else {
            return false;
        }
    }

    function isOutLine() external view returns (bool) {
        if (
            ((snapshoots.length == 0 ||
                snapshoots[snapshoots.length - 1].executerId !=
                Isenator(Iconf(conf).senator()).executerId()) &&
                block.timestamp +
                    Iconf(conf).executEpoch() -
                    Iconf(conf).stEpoch() >
                Isenator(Iconf(conf).senator()).executerIndate()) ||
            (snapshoots[snapshoots.length - 1].result == Result.PENDING &&
                block.timestamp >
                snapshoots[snapshoots.length - 1].proposalTime +
                    Iconf(conf).voteEpoch())
        ) {
            return true;
        } else {
            return false;
        }
    }
}
