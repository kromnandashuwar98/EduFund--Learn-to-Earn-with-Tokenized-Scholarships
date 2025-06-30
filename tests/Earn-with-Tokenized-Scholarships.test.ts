import { Clarinet, Tx, Chain, Account, types } from '@stacks/transactions';

Clarinet.test({
  name: "Ensures student registration works",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const student = accounts.get("wallet_1")!;

    let block = chain.mineBlock([
      Tx.contractCall(
        "Earn-with-Tokenized-Scholarships",
        "register-student",
        [types.ascii("John Doe"), types.ascii("Computer Science"), types.uint(4)],
        student.address
      )
    ]);
    block.receipts[0].result.expectOk().expectBool(true);
  }
});

Clarinet.test({
  name: "Ensures scholarship creation works",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const donor = accounts.get("wallet_2")!;
    const student = accounts.get("wallet_1")!;

    chain.mineBlock([
      Tx.contractCall(
        "Earn-with-Tokenized-Scholarships",
        "register-student",
        [types.ascii("John Doe"), types.ascii("Computer Science"), types.uint(4)],
        student.address
      )
    ]);

    let block = chain.mineBlock([
      Tx.contractCall(
        "Earn-with-Tokenized-Scholarships",
        "create-scholarship",
        [types.principal(student.address), types.uint(2000), types.uint(4)],
        donor.address
      )
    ]);
    block.receipts[0].result.expectOk().expectUint(1);
  }
});
