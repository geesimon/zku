import { Field, isReady, shutdown } from 'snarkyjs';
import { deploy, update } from './index';

describe('index.ts', () => {
  describe('foo()', () => {
    beforeAll(async () => {
      await isReady;
    });
    afterAll(async () => {
      await shutdown();
    });
    it('update with correct parameters should be alright', async () => {      
      let snapIntance = await deploy();
      // 99 = 9 * 11
      expect(await update(snapIntance, Field(9), Field(11), Field(99))).toBe(true);
    });
    it('update with wrong parameters should fail', async () => {      
      let snapIntance =  await deploy();
      // 990 != 9 * 11
      expect(await update(snapIntance, Field(9), Field(11), Field(990))).toBe(false);
    });
  });
});
