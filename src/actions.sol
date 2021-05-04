// actions.sol -- Tinlake actions
// Copyright (C) 2020 Centrifuge

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import "ds-note/note.sol";

pragma solidity >=0.5.15 <0.6.0;

interface NFTLike {
    function approve(address usr, uint token) external;
    function transferFrom(address src, address dst, uint token) external;
}

interface ERC20Like {
    function approve(address usr, uint amount) external;
    function transfer(address dst, uint amount) external;
    function transferFrom(address src, address dst, uint amount) external;
}

interface ShelfLike {
    function pile() external returns(address);
    function lock(uint loan) external;
    function unlock(uint loan) external;
    function issue(address registry, uint token) external returns(uint loan);
    function close(uint loan) external;
    function borrow(uint loan, uint amount) external;
    function withdraw(uint loan, uint amount, address usr) external;
    function repay(uint loan, uint amount) external;
    function shelf(uint loan) external returns(address registry,uint256 tokenId,uint price,uint principal, uint initial);
}

interface PileLike {
    function debt(uint loan) external returns(uint);
}

contract Actions is DSNote {
    function approveNFT(address registry, address usr, uint token) public {
        NFTLike(registry).approve(usr, token);
    }

    function approveERC20(address erc20, address usr, uint amount) public {
        ERC20Like(erc20).approve(usr, amount);
    }

    function transferERC20(address erc20, address dst, uint amount) public {
        ERC20Like(erc20).transfer(dst, amount);
    }

    // --- Borrower Actions ---

    function issue(address shelf, address registry, uint token) note public returns (uint loan) {
        loan = ShelfLike(shelf).issue(registry, token);
        // proxy approve shelf to take nft
        NFTLike(registry).approve(shelf, token);
        return loan;
    }

    function transferIssue(address shelf, address registry, uint token) note public returns (uint loan) {
        // transfer nft from borrower to proxy
        NFTLike(registry).transferFrom(msg.sender, address(this), token);
        return issue(shelf, registry, token);
    }

    function lock(address shelf, uint loan) public {
        ShelfLike(shelf).lock(loan);
    }

    function borrowWithdraw(address shelf, uint loan, uint amount, address usr) public {
        ShelfLike(shelf).borrow(loan, amount);
        ShelfLike(shelf).withdraw(loan, amount, usr);
    }

    function lockBorrowWithdraw(address shelf, uint loan, uint amount, address usr) public {
        ShelfLike(shelf).lock(loan);
        borrowWithdraw(shelf, loan, amount, usr);
    }

    function transferIssueLockBorrowWithdraw(address shelf, address registry, uint token, uint amount, address usr) public {
        uint loan = transferIssue(shelf, registry, token);
        lockBorrowWithdraw(shelf, loan, amount, usr);
    }

    function repay(address shelf, address erc20, uint loan, uint amount) public {
        require(amount <= PileLike(ShelfLike(shelf).pile()).debt(loan), "amount-larger-than-debt");

        // transfer money from borrower to proxy
        ERC20Like(erc20).transferFrom(msg.sender, address(this), amount);
        ERC20Like(erc20).approve(address(shelf), amount);
        ShelfLike(shelf).repay(loan, amount);
    }

    function repayFullDebt(address shelf, address pile, address erc20, uint loan) public {
        repay(shelf, erc20, loan, PileLike(pile).debt(loan));
    }

    function unlock(address shelf, address registry, uint token, uint loan) public {
        ShelfLike(shelf).unlock(loan);
        NFTLike(registry).transferFrom(address(this), msg.sender, token);
    }

    function close(address shelf, uint loan) public {
        ShelfLike(shelf).close(loan);
    }

    function repayUnlock(address shelf, address pile, address registry, uint token, address erc20, uint loan) public {
        repayFullDebt(shelf, pile, erc20, loan);
        unlock(shelf, registry, token, loan);
    }

    function repayUnlockClose(address shelf, address pile, address registry, uint token, address erc20, uint loan) public {
        repayUnlock(shelf, pile, registry, token, erc20, loan);
        ShelfLike(shelf).close(loan);
    }

    function unlockClose(address shelf, uint loan) public {
        ShelfLike(shelf).unlock(loan);
        ShelfLike(shelf).close(loan);
    }
}
