import { 
  Field, 
  SmartContract, 
  Mina,
  state, 
  State,
  isReady,
  method, 
  UInt64,
  Party,
  PrivateKey
} from 'snarkyjs';

export { deploy, update }

await isReady;

/// @Title TriNumber contract initializes 3 state variables: num1, num2, num3
/// and make sure: num3 = num1 * num2.
export default class TriNumber extends SmartContract {
  @state(Field) num1 = State<Field>();
  @state(Field) num2 = State<Field>();
  @state(Field) num3 = State<Field>();

  // initialization
  deploy(initialBalance: UInt64, 
          _num1: Field,
          _num2: Field) {
    super.deploy();
    this.balance.addInPlace(initialBalance);
    this.num1.set(_num1);
    this.num2.set(_num2);
    this.num3.set(_num1.mul(_num2));
  }

  // Update num1, num2 and num3. Check num3 = num1 * num2
  @method async update(_num1: Field, _num2: Field, _num3: Field) {    
    const newNum3 = _num1.mul(_num2);
    newNum3.assertEquals(_num3);

    this.num1.set(_num1);
    this.num2.set(_num1);
    this.num3.set(newNum3);
  }
}

// setup
const Local = Mina.LocalBlockchain();
Mina.setActiveInstance(Local);
const account1 = Local.testAccounts[0].privateKey;
const account2 = Local.testAccounts[1].privateKey;

const snappPrivkey = PrivateKey.random();
let snappAddress = snappPrivkey.toPublicKey();

// let snappInstance: TriNumber;

// deploy smart contract
async function deploy() {
  let snappInstance = new TriNumber(snappAddress);

  let tx = Mina.transaction(account1, async () => {
    const initialBalance = UInt64.fromNumber(1000000);
    const p = await Party.createSigned(account2);
    p.balance.subInPlace(initialBalance);    
    snappInstance.deploy(initialBalance, Field(1), Field(2));
  });
  await tx.send().wait();
  
  return snappInstance;
}

// call TriNumber::update 
async function update(_snapInstance: TriNumber, _num1: Field, _num2: Field, _num3: Field) {
    let result = true;
    // Update the snapp
    await Mina.transaction(account1, async () => {
      await _snapInstance.update(_num1, _num2, _num3);
    })
      .send()
      .wait()
      .catch((e) => result = false);
  
    return  result;
}