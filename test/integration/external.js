// Developer solves bitcorelib issue with this one weird trick!
// Source: https://github.com/bitpay/bitcore/issues/1457#issuecomment-467594031
Object.defineProperty(global, '_bitcore', { get(){ return undefined }, set(){} }); // eslint-disable-line

const getValue = require('../../nexusmutual/test/utils/getMCRPerThreshold.js').getValue;
module.exports = {
  getValue,
};
