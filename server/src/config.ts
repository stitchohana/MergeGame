import dotenv from "dotenv";
dotenv.config();

const jwtSecret = process.env.JWT_SECRET || "";
if (!jwtSecret) {
  console.error("[config] FATAL: JWT_SECRET environment variable is required. Exiting.");
  process.exit(1);
}

export const config = {
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
