import { createStorageProvider } from './factory';
import { authorizeCouple, extractCoupleId, resolveUid, validateObjectKey } from './auth';

/**
 * Trace · 同迹 — 云函数入口
 *
 * 对外固定三个接口（客户端不感知任何存储厂商）：
 *   POST /storage/get_upload_sign   → { url }
 *   POST /storage/get_download_sign → { url }
 *   POST /storage/delete_object     → { ok }
 *
 * 请求体：{ "objectKey": "<coupleId>/<fileKey>" }
 * 执行顺序：鉴权 → 校验 key → 校验情侣空间归属 → 签名/删除
 */

type Req = {
  headers?: Record<string, string | string[] | undefined>;
  body?: unknown;
};

type Res = {
  status: (code: number) => { json: (data: unknown) => unknown };
  json: (data: unknown) => unknown;
};

const UPLOAD_EXPIRE = 900; // 15 分钟
const DOWNLOAD_EXPIRE = 1800; // 30 分钟

async function handle(
  req: Req,
  res: Res,
  op: 'upload' | 'download' | 'delete',
): Promise<unknown> {
  const fail = (code: number, message: string) =>
    res.status(code).json({ error: message });

  // 1. 鉴权
  const uid = resolveUid(req);
  if (!uid) {
    return fail(401, 'unauthorized');
  }

  // 2. 校验 objectKey
  const body = (req.body ?? {}) as { objectKey?: unknown };
  if (!validateObjectKey(body.objectKey)) {
    return fail(400, 'invalid object_key');
  }
  const objectKey = body.objectKey;

  // 3. 校验当前用户属于该情侣空间
  const coupleId = extractCoupleId(objectKey);
  try {
    const allowed = await authorizeCouple(uid, coupleId);
    if (!allowed) {
      return fail(403, 'forbidden');
    }
  } catch (e) {
    return fail(500, `auth_check_failed: ${(e as Error).message}`);
  }

  // 4. 调用对应厂商适配器
  try {
    const provider = createStorageProvider();
    if (op === 'upload') {
      const url = await provider.getUploadUrl(objectKey, UPLOAD_EXPIRE);
      return res.status(200).json({ url });
    }
    if (op === 'download') {
      const url = await provider.getDownloadUrl(objectKey, DOWNLOAD_EXPIRE);
      return res.status(200).json({ url });
    }
    await provider.delete(objectKey);
    return res.status(200).json({ ok: true });
  } catch (e) {
    return fail(500, `storage_error: ${(e as Error).message}`);
  }
}

export const getUploadSign = (req: Req, res: Res) => handle(req, res, 'upload');
export const getDownloadSign = (req: Req, res: Res) => handle(req, res, 'download');
export const deleteObject = (req: Req, res: Res) => handle(req, res, 'delete');

/** Express 风格路由注册（若云函数平台支持 Express 可直接挂载） */
export function registerRoutes(app: { post: (p: string, h: unknown) => void }): void {
  app.post('/storage/get_upload_sign', getUploadSign);
  app.post('/storage/get_download_sign', getDownloadSign);
  app.post('/storage/delete_object', deleteObject);
}
