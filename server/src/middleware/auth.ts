import { jwtVerify, SignJWT } from "jose";
import { NextFunction, WorkerRequest as Request, WorkerResponse as Response } from "../worker/http";

export interface AuthPayload {
  userId: string;
  deviceId: string;
}

const encoder = new TextEncoder();

export function createAuthRequired(jwtSecret: string) {
  const key = encoder.encode(jwtSecret);
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
  const header = req.headers.authorization;
  if (!header || !header.startsWith("Bearer ")) {
    res.status(401).json({ error: "missing_authorization" });
    return;
  }

  const token = header.slice(7);
    try {
      const { payload } = await jwtVerify(token, key, { algorithms: ["HS256"] });
      if (typeof payload.userId !== "string" || typeof payload.deviceId !== "string") {
        throw new Error("invalid_payload");
      }
      req.auth = { userId: payload.userId, deviceId: payload.deviceId };
      await next();
  } catch {
    res.status(401).json({ error: "invalid_token" });
  }
  };
}

export async function signToken(payload: AuthPayload, jwtSecret: string): Promise<string> {
  return new SignJWT(payload as unknown as Record<string, unknown>)
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setIssuedAt()
    .setExpirationTime("7d")
    .sign(encoder.encode(jwtSecret));
}
