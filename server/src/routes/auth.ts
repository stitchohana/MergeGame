import { Router, Request, Response } from "express";
import { IStorage } from "../storage/interface";
import { signToken } from "../middleware/auth";

export function createAuthRouter(storage: IStorage): Router {
  const router = Router();

  // POST /api/auth/login — device ID login
  router.post("/login", async (req: Request, res: Response) => {
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
      } else {
        console.log(`[auth] user login: ${user.userId} (device=${device_id})`);
      }

      const token = signToken({ userId: user.userId, deviceId: user.deviceId });

      res.json({
        token,
        user: {
          user_id: user.userId,
          device_id: user.deviceId,
          created_at: user.createdAt,
        },
      });
    } catch (err) {
      console.error("[auth] login error:", err);
      res.status(500).json({ error: "internal_error" });
    }
  });

  return router;
}
