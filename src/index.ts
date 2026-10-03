import { readConfig } from './config.js';
import { createApp } from './app.js';
import { startTelegramWorker } from './telegram.js';
const config = readConfig();
const { app, upgrade } = createApp(config);
const server = app.listen(config.port, '::', () => console.log('Team Task Hub backend ready on port ' + config.port));
server.on('upgrade', upgrade);
const stopWorker = startTelegramWorker(config);
function shutdown() {
  stopWorker();
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 10_000).unref();
}
process.once('SIGTERM', shutdown);
process.once('SIGINT', shutdown);
