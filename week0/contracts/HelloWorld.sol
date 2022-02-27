// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

/**
* @title "Hello World" contract
* @author Simon Ji
* @notice Simple contract that stores an unsigned integer and then retrieve it
*/
contract HelloWorld {

    uint256 number;

    /**
     * @dev Store value in variable
     * @param _num value to store
     */
    function store(uint256 _num) external {
        number = _num;
    }

    /**
     * @dev Return value 
     * @return value of 'number'
     */
    function retrieve() external view returns (uint256){
        return number;
    }

    /**
     * @dev Store an unsigned integer and then retrieve it
     * @param _num value to store
     * @return value of stored number
     */
    // function storeAndRetrieve(uint256 _num) public returns (uint256) {
    //     store(_num);
    //     // _num = retrieve();
    //     return _num;
    // }
}
