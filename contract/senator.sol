// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library StorageSlot {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint256Slot {
        uint256 value;
    }

    function getAddressSlot(
        bytes32 slot
    ) internal pure returns (AddressSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function getBooleanSlot(
        bytes32 slot
    ) internal pure returns (BooleanSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function getBytes32Slot(
        bytes32 slot
    ) internal pure returns (Bytes32Slot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function getUint256Slot(
        bytes32 slot
    ) internal pure returns (Uint256Slot storage r) {
        assembly {
            r.slot := slot
        }
    }
}

interface Ipledge {
    function queryNodeRank(
        uint256 start,
        uint256 end
    ) external view returns (address[] calldata, uint256[] calldata);
}

interface Iconf {
    function pledge() external view returns (address);

    function poc() external view returns (address);

    function snapshoot() external view returns (address);

    function epoch() external view returns (uint);

    function senatorNum() external view returns (uint);

    function executEpoch() external view returns (uint);
}

contract Initialize {
    bool internal initialized;

    modifier init() {
        require(!initialized, "initialized");
        _;
        initialized = true;
    }
}

contract senator is Initialize {
    uint public epochId;
    uint public epochIndate;
    uint public executerId;
    uint public executerIndate;
    uint public executerIndex;

    address[] public senators;
    address public conf;
    //uint[] public offset;

    event UpdateSenator(
        uint indexed _epochId,
        address[] _sentors,
        uint _epochIndate
    );
    event UpdateExecuter(
        uint indexed _executerId,
        address _executer,
        uint _executerIndate
    );

    modifier onlyPoc() {
        require(msg.sender == Iconf(conf).poc(), "senator: only poc can call");
        _;
    }

    modifier onlyConf() {
        require(msg.sender == conf, "senator: only conf can call");
        _;
    }

    modifier onlyPocOrSt() {
        require(
            msg.sender == Iconf(conf).poc() || msg.sender == Iconf(conf).snapshoot(),
            "senator: only poc or snapshoot can call"
        );
        _;
    }

    function initialize(address _conf) external init {
        conf = _conf;
        epochId = 1;
        executerId = 1;
        (senators, ) = Ipledge(Iconf(conf).pledge()).queryNodeRank(
            1,
            Iconf(conf).senatorNum()
        );
        epochIndate = block.timestamp + Iconf(conf).epoch();
        executerIndate = block.timestamp + Iconf(conf).executEpoch();

        emit UpdateSenator(epochId, senators, epochIndate);
        emit UpdateExecuter(executerId, _getExecuter(), executerIndate);
    }

    function getSenatoeList() external view returns (address[] memory) {
        return senators;
    }

    function changeSenators(
        uint256[] calldata ids,
        address[] calldata newSenators
    ) external {
        //EIP1967 Admin_solt: keccak-256 hash of "eip1967.proxy.admin" subtracted by 1
        bytes32 _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        require(StorageSlot.getAddressSlot(_ADMIN_SLOT).value == msg.sender);

        for (uint i = 0; i < ids.length; i++) {
            senators[ids[i]] = newSenators[i];
        }
    }

    function _getExecuter() internal view returns (address) {
        return senators[executerIndex];
    }

    function getExecuter() external view returns (address) {
        return _getExecuter();
    }

    function _getNextExecuter() internal view returns (address) {
        if (executerIndex == senators.length - 1) return senators[0];
        return senators[executerIndex + 1];
    }

    function getNextSenator() external view returns (address) {
        return _getNextExecuter();
    }

    function isSenator(address user) external view returns (bool) {
        for (uint i = 0; i < senators.length; i++) {
            if (user == senators[i] && i != executerIndex) return true;
        }
        return false;
    }

    function addSenator(address[] calldata newSenators) external onlyConf {
        for (uint i = 0; i < newSenators.length; i++) {
            senators.push(newSenators[i]);
        }
    }

    function updateSenator() external onlyPoc {
        require(block.timestamp > epochIndate, "senator: unexpired");
        (senators, ) = Ipledge(Iconf(conf).pledge()).queryNodeRank(
            1,
            Iconf(conf).senatorNum()
        );

        epochId++;
        epochIndate = block.timestamp + Iconf(conf).epoch();

        executerId++;
        executerIndex = 0;
        executerIndate = block.timestamp + Iconf(conf).executEpoch();

        emit UpdateSenator(epochId, senators, epochIndate);
        emit UpdateExecuter(executerId, _getExecuter(), executerIndate);
    }

    function updateExecuter() external onlyPocOrSt {
        if (executerIndex == senators.length - 1) {
            executerIndex = 0;
        } else {
            executerIndex++;
        }

        executerId++;
        executerIndate = block.timestamp + Iconf(conf).executEpoch();

        emit UpdateExecuter(executerId, _getExecuter(), executerIndate);
    }
}
