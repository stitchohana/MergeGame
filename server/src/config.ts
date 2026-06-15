const jwtSecret = process.env.JWT_SECRET;
if (!jwtSecret) {
  console.warn("[config] WARNING: JWT_SECRET not set, using insecure default. Set JWT_SECRET in production.");
}

export const config = {
  port: parseInt(process.env.PORT || "3000", 10),
  jwtSecret: jwtSecret || "mergegame-dev-secret-change-in-production",
  jwtExpiresIn: "2h",
  dbType: process.env.DB_TYPE || "json_file",
  jsonDbPath: process.env.JSON_DB_PATH || "./data",
  game: {
    gridCols: 7,
    gridRows: 9,
  },
};
