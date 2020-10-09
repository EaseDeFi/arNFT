pragma solidity ^0.6.6;

import '../general/SafeMath.sol';
import '../general/Ownable.sol';
import '../interfaces/IERC20.sol';

/**
 * @dev BorrowManager is where borrowers do all their interaction and it holds funds
 *      until they're sent to the StakeManager.
 **/
contract BalanceManager is Ownable {

    using SafeMath for uint;

    IERC20 public dai;

    // keep track of monthly payments and start/end of those
    mapping (address => Balance) balances;

    // With lastTime and secondPrice we can determine balance by second.
    struct Balance {
        uint256 lastTime;
        uint256 secondPrice;
        uint256 lastBalance;
    }

    /**
     * @dev Call updateBalance before any action is taken by a user.
     * @param _user The user whose balance we need to update.
     **/
    modifier update(address _user)
    {
        updateBalance(_user);
        _;
    }


    /**
     * @param _dai The address of the Dai contract.
     **/
    constructor(address _dai)
    public
    {
        dai = IERC20(_dai);
    }

    /**
     * @dev Borrower deposits an amount of Dai to pay for coverage.
     * @param _amount The amount of Dai to deposit.
     * @notice Borrower must first approve this contract to withdraw Dai.
     **/
    function deposit(uint56 _amount) 
    external
    update(msg.sender)
    {
        require(dai.transferFrom(msg.sender, address(this), _amount), "Dai deposit transfer unsuccessful.");

        balances[msg.sender].lastBalance = balances[msg.sender].lastBalance.add(_amount);
        balances[msg.sender].lastTime = block.timestamp;
    }

    /**
     * @dev Borrower withdraws Dai from the contract.
     * @param _amount The amount of Dai to withdraw.
     **/
    function withdraw(uint256 _amount)
    external
    update(msg.sender)
    {
        Balance memory balance = balances[msg.sender];

        require(_amount <= balance.lastBalance, "Not enough balance for withdrawal.");

        balance.lastBalance = balance.lastBalance.sub(_amount);
        balances[msg.sender] = balance;

        require(dai.transfer(msg.sender, _amount), "Dai withdrawal transfer unsuccessful.");
    }

    /**
    * @dev Find the current balance of a user to the second.
    * @param _user The user whose balance to find.
        **/
    function balanceOf(address _user)
    public
    view
    returns (uint256)
    {
        Balance memory balance = balances[_user];

        // We adjust balance on chain based on how many blocks have passed.
        uint256 lastBalance = balance.lastBalance;

        uint256 timeElapsed = block.timestamp.sub(balance.lastTime);
        uint256 cost = timeElapsed * balance.secondPrice;

        // If the elapsed time has brought balance to 0, make it 0.
        uint256 newBalance;
        if (lastBalance > cost) newBalance = lastBalance.sub(cost);
        else newBalance = 0;

        return newBalance;
    }

    /**
    * @dev Update a borrower's balance to it's adjusted amount.
    * @param _user The address to be updated.
        **/
    function updateBalance(address _user)
    public
    {
        Balance memory balance = balances[_user];

        // The new balance that a user will have.
        uint256 newBalance = balanceOf(_user);

        // newBalance should never be greater than last balance.
        uint256 loss = balance.lastBalance.sub(newBalance);

        // Kind of a weird way to do it, but we're giving owner the balance.
        balances[_user].lastBalance += loss;

        // Update storage balance.
        balance.lastBalance = newBalance;
        balance.lastTime = block.timestamp;
        balances[_user] = balance;
    }

    /**
     * @dev Armor has the ability to change the price that a user is paying for their insurance.
     * @param _user The user whose price we are changing.
     * @param _newPrice the new price per second that the user will be paying.
     **/
    function changePrice(address _user, uint256 _newPrice)
    external
    onlyOwner
    {
        balances[_user].secondPrice = _newPrice;
    }

}
