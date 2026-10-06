import { pathToFileURL } from "node:url";
import { resolve } from "node:path";
await import(pathToFileURL(resolve(process.argv[2], "P.js")).href);
