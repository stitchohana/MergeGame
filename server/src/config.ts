export const config = {
  port: parseInt(process.env.PORT || "3000", 10),
  jwtSecret: process.env.JWT_SECRET || "mergegame-dev-secret-change-in-production",
  jwtExpiresIn: "2h",
  dbType: process.env.DB_TYPE || "json_file",
  jsonDbPath: process.env.JSON_DB_PATH || "./data",
  game: {
    gridCols: 7,
    gridRows: 9,
  },
};
