import {
  Field,
  prop,
  PublicKey,
  CircuitValue,
  Signature,
  UInt64,
  UInt32,
  KeyedAccumulatorFactory,
  ProofWithInput,
  proofSystem,
  branch,
  MerkleStack,
  shutdown,
} from 'snarkyjs';

const AccountDbDepth: number = 32;
const AccountDb = KeyedAccumulatorFactory<PublicKey, RollupAccount>(
  AccountDbDepth
);
type AccountDb = InstanceType<typeof AccountDb>;

class RollupAccount extends CircuitValue {
  @prop balance: UInt64;
  @prop nonce: UInt32;
  @prop publicKey: PublicKey;

  constructor(balance: UInt64, nonce: UInt32, publicKey: PublicKey) {
    super();
    this.balance = balance;
    this.nonce = nonce;
    this.publicKey = publicKey;
  }
}

class RollupTransaction extends CircuitValue {
  @prop amount: UInt64;
  @prop nonce: UInt32;
  @prop sender: PublicKey;
  @prop receiver: PublicKey;

  constructor(
    amount: UInt64,
    nonce: UInt32,
    sender: PublicKey,
    receiver: PublicKey
  ) {
    super();
    this.amount = amount;
    this.nonce = nonce;
    this.sender = sender;
    this.receiver = receiver;
  }
}

class RollupDeposit extends CircuitValue {
  @prop publicKey: PublicKey;
  @prop amount: UInt64;
  constructor(publicKey: PublicKey, amount: UInt64) {
    super();
    this.publicKey = publicKey;
    this.amount = amount;
  }
}

class RollupState extends CircuitValue {
  @prop pendingDepositsCommitment: Field;
  @prop accountDbCommitment: Field;
  constructor(p: Field, c: Field) {
    super();
    this.pendingDepositsCommitment = p;
    this.accountDbCommitment = c;
  }
}

class RollupStateTransition extends CircuitValue {
  @prop source: RollupState;
  @prop target: RollupState;
  constructor(source: RollupState, target: RollupState) {
    super();
    this.source = source;
    this.target = target;
  }
}

// a recursive proof system is kind of like an "enum"
@proofSystem
class RollupProof extends ProofWithInput<RollupStateTransition> {
  // Create proof for fund deposit 
  @branch static processDeposit(
    pending: MerkleStack<RollupDeposit>,
    accountDb: AccountDb
  ): RollupProof {
    // Retreive pending deposit
    let before = new RollupState(pending.commitment, accountDb.commitment());
    let deposit = pending.pop();
    // Retreive rollup account 
    let [{ isSome }, mem] = accountDb.get(deposit.publicKey);
    isSome.assertEquals(false);

    // Assign public key to this rollup account 
    let account = new RollupAccount(
      UInt64.zero,
      UInt32.zero,
      deposit.publicKey
    );
    // Update account info
    accountDb.set(mem, account);

    // commit state change
    let after = new RollupState(pending.commitment, accountDb.commitment());

    // Generate proof for this state change caused by deposit
    return new RollupProof(new RollupStateTransition(before, after));
  }

  // Create proof for transaction: sender transfer fund to receiver
  @branch static transaction(
    t: RollupTransaction,
    s: Signature,
    pending: MerkleStack<RollupDeposit>,
    accountDb: AccountDb
  ): RollupProof {
    // Verify signature using sender's public key 
    s.verify(t.sender, t.toFields()).assertEquals(true);
    // Retreive pending transaction
    let stateBefore = new RollupState(
      pending.commitment,
      accountDb.commitment()
    );

    // Retreive sender account
    let [senderAccount, senderPos] = accountDb.get(t.sender);
    senderAccount.isSome.assertEquals(true);
    senderAccount.value.nonce.assertEquals(t.nonce);

    // Deduct sender's account balance
    senderAccount.value.balance = senderAccount.value.balance.sub(t.amount);
    // Increase sender's nonce
    senderAccount.value.nonce = senderAccount.value.nonce.add(1);

    // Update sender account info
    accountDb.set(senderPos, senderAccount.value);

    // Retreive receiver account
    let [receiverAccount, receiverPos] = accountDb.get(t.receiver);
    // Increase receiver's account balance
    receiverAccount.value.balance = receiverAccount.value.balance.add(t.amount);
    // Update receiver's account info
    accountDb.set(receiverPos, receiverAccount.value);

    // Commit state change
    let stateAfter = new RollupState(
      pending.commitment,
      accountDb.commitment()
    );
    // Generate proof for the state change
    return new RollupProof(new RollupStateTransition(stateBefore, stateAfter));
  }

  // Creat recursive proof by proving correct transition from
  // p1.publicInput.source to p2.publicInput.target
  @branch static merge(p1: RollupProof, p2: RollupProof): RollupProof {
    // Check p1 and p2 is connected correctly
    p1.publicInput.target.assertEquals(p2.publicInput.source);
    // Generate proof for the state change: before state (presented/verified by) p1 to
    // after state (presented/verified by) p2
    return new RollupProof(
      new RollupStateTransition(p1.publicInput.source, p2.publicInput.target)
    );
  }
}

shutdown();

export {RollupAccount, RollupDeposit, RollupState, RollupStateTransition, RollupTransaction, RollupProof}
