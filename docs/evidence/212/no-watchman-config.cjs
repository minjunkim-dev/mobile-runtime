const path = require('node:path');
const config = require(path.join(process.env.BASELINE_APP_ROOT, 'metro.config.js'));
module.exports = {...config, resolver: {...config.resolver, useWatchman: false}};
