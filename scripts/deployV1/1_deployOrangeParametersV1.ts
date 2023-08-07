import { Deploy } from "../common";

async function main() {
  await Deploy("OrangeParametersV1");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
