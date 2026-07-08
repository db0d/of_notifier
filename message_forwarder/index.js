const SmeeClient = require('smee-client');

const source = process.env.SMEE_URL;
const target = process.env.TARGET_URL;

if (!source) {
  console.error('Error: SMEE_URL environment variable is required');
  process.exit(1);
}

if (!target) {
  console.error('Error: TARGET_URL environment variable is required');
  process.exit(1);
}

console.log(`Forwarding ${source} -> ${target}`);

const smee = new SmeeClient({ source, target, logger: console });

const events = smee.start();

process.on('SIGINT', () => {
  events.close();
  process.exit(0);
});
