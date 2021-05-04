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

pragma solidity ^0.5.3;

contract NFTLike {
    function approve(address usr, uint token) public;
    function transferFrom(address sender, address recipient, uint token) public;
}

contract ERC20Like {
    function approve(address usr, uint amount) public;
    function transferFrom(address sender, address recipient, uint amount) public;
}

contract ShelfLike {
    function lock(uint loan) public;
    function unlock(uint loan) public;
    function issue(address registry, uint token) public returns(uint loan);
    function close(uint loan) public;
    function borrow(uint loan, uint amount) public;
    function withdraw(uint loan, uint amount, address usr) public;
    function repay(uint loan, uint amount) public;
    function shelf(uint loan) public returns(address registry,uint256 tokenId,uint price,uint principal, uint initial);
}

contract PileLike {
    function debt(uint loan) public returns(uint);
}

contract Actions is DSNote {
    function approveNFT(NFTLike registry, address usr, uint token) public {
        registry.approve(usr, token);
    }

    function approveERC20(ERC20Like erc20, address usr, uint amount) public {
        erc20.approve(usr, amount);
    }

    function transferFromERC20(ERC20Like erc20, address src, address dst, uint amount) public {
        erc20.transferFrom(src, dst, amount);
    }

    // --- Borrower Actions ---

    function issue(ShelfLike shelf, NFTLike registry, uint token) note public returns (uint loan) {
        loan = shelf.issue(address(registry), token);
        // proxy approve shelf to take nft
        registry.approve(address(shelf), token);
        return loan;
    }

    function transferIssue(ShelfLike shelf, NFTLike registry, uint token) note public returns (uint loan) {
        // transfer nft from borrower to proxy
        registry.transferFrom(msg.sender, address(this), token);
        return issue(shelf, registry, token);
    }

    function lock(ShelfLike shelf, uint loan) public {
        shelf.lock(loan);
    }

    function borrowWithdraw(ShelfLike shelf, uint loan, uint amount, address usr) public {
        shelf.borrow(loan, amount);
        shelf.withdraw(loan, amount, usr);
    }

    function lockBorrowWithdraw(ShelfLike shelf, uint loan, uint amount, address usr) public {
        shelf.lock(loan);
        borrowWithdraw(shelf, loan, amount, usr);
    }

    function transferIssueLockBorrowWithdraw(ShelfLike shelf, NFTLike registry, uint token, uint amount, address usr) public {
        uint loan = transferIssue(shelf, registry, token);
        lockBorrowWithdraw(shelf, loan, amount, usr);
    }

    function repay(ShelfLike shelf, ERC20Like erc20, uint loan, uint amount) public {
        // transfer money from borrower to proxy
        erc20.transferFrom(msg.sender, address(this), amount);
        erc20.approve(address(shelf), amount);
        shelf.repay(loan, amount);
    }

    function repayFullDebt(ShelfLike shelf, PileLike pile, ERC20Like erc20, uint loan) public {
        uint debt = pile.debt(loan);
        repay(shelf, erc20, loan, debt);
    }

    function unlock(ShelfLike shelf, NFTLike registry, uint token, uint loan) public {
        shelf.unlock(loan);
        registry.transferFrom(address(this), msg.sender, token);
    }

    function close(ShelfLike shelf, uint loan) public {
        shelf.close(loan);
    }

    function repayUnlock(ShelfLike shelf, PileLike pile, NFTLike registry, uint token, ERC20Like erc20, uint loan) public {
        repayFullDebt(shelf, pile, erc20, loan);
        unlock(shelf, registry, token, loan);
    }

    function repayUnlockClose(ShelfLike shelf, PileLike pile, NFTLike registry, uint token, ERC20Like erc20, uint loan) public {
        repayUnlock(shelf, pile, registry, token, erc20, loan);
        shelf.close(loan);
    }

    function unlockClose(ShelfLike shelf, uint loan) public {
        shelf.unlock(loan);
        shelf.close(loan);
    }
}
