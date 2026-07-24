"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createAuthRouter = createAuthRouter;
const http_1 = require("../worker/http");
const auth_1 = require("../middleware/auth");
function createAuthRouter(storage, jwtSecret) {
    const router = new http_1.Router();
    // POST /api/auth/login — device ID login
    router.post("/login", async (req, res) => {
        try {
            const { device_id } = req.body;
            if (!device_id || typeof device_id !== "string" || device_id.trim().length === 0) {
                res.status(400).json({ error: "device_id_required" });
                return;
            }
            if (device_id.length > 128) {
                res.status(400).json({ error: "device_id_too_long" });
                return;
            }
            let user = await storage.findUser(device_id);
            if (!user) {
                user = await storage.createUser(device_id);
                console.log(`[auth] new user registered: ${user.userId} (device=${device_id})`);
            }
            else {
                console.log(`[auth] user login: ${user.userId} (device=${device_id})`);
            }
            const token = await (0, auth_1.signToken)({ userId: user.userId, deviceId: user.deviceId }, jwtSecret);
            res.json({
                token,
                user: {
                    user_id: user.userId,
                    device_id: user.deviceId,
                    created_at: user.createdAt
                }
            });
        }
        catch (err) {
            console.error("[auth] login error:", err);
            res.status(500).json({ error: "internal_error" });
        }
    });
    return router;
}
