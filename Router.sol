pragma solidity ^0.4.25;


contract Router {

    function route(address addr)
        public 
        payable
    {
        uint256 amount  = msg.value;
        addr.transfer(amount);
    }
    
}