"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.config = void 0;
const dotenv_1 = __importDefault(require("dotenv"));
dotenv_1.default.config();
const jwtSecret = process.env.JWT_SECRET || "";
if (!jwtSecret) {
    console.error("[config] FATAL: JWT_SECRET environment variable is required. Exiting.");
    process.exit(1);
}
exports.config = {
    port: parseInt(process.env.PORT || "3000", 10),
    jwtSecret,
    jwtExpiresIn: process.env.JWT_EXPIRES || "30d",
    dbType: process.env.DB_TYPE || "json_file",
    jsonDbPath: process.env.JSON_DB_PATH || "./data",
    game: {
        gridCols: 7,
        gridRows: 9
    }
};
