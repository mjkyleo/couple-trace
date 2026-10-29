import jwt from 'jsonwebtoken';
import { createClient, SupabaseClient } from '@supabase/supabase-js';

/**
 * objectKey 合法格式：<coupleId>/<文件名或子路径>
 * - coupleId 段：1~64 位字母数字连字符（UUID）
 * - 文件路径段：1~512 位字母数字、点、下划线、斜杠、连字符
 */
const OBJECT_KEY_RE = /^[A-Za-z0-9-]{1,64}\/[A-Za-z0-9._/-]{1,512}$/;

/** 校验 objectKey，拦截路径穿越等非法输入 */
export function validateObjectKey(key: unknown): key is string {
  if (typeof key !== 'string' || key.length === 0 || key.length > 600) {
    return false;
  }
  if (key.includes('..')) {
    return false;
  }
  if (key.startsWith('/') || key.endsWith('/')) {
    return false;
  }
  return OBJECT_KEY_RE.test(key);
}

/** 从 objectKey 提取情侣空间 id（第一段） */
export function extractCoupleId(key: string): string {
  return key.split('/')[0];
}

/**
 * 从请求中解析用户 id。生产路径只有一条：
 *   Authorization: Bearer <JWT> → jwt.verify 验签成功后取 payload.sub
 *
 * 验签密钥取自 TRACE_JWT_SECRET（回退 SUPABASE_JWT_SECRET），即 MemFire/Supabase
 * 项目的 JWT 密钥。未配置密钥时一律拒绝，绝不退化成 jwt.decode —— 否则任何人
 * 自签一个无签名 token 即可冒充任意用户。
 *
 * 本地开发需要免签 token 或 X-Trace-User-Id 头时，必须显式设置
 * TRACE_ALLOW_INSECURE_DEV_AUTH=1；该开关在生产部署中必须保持关闭。
 */
export function resolveUid(req: {
  headers?: Record<string, string | string[] | undefined>;
}): string | null {
  const insecureDevAuth =
    process.env.TRACE_ALLOW_INSECURE_DEV_AUTH === '1';
  const secret =
    process.env.TRACE_JWT_SECRET ?? process.env.SUPABASE_JWT_SECRET;

  const auth = req.headers?.['authorization'];
  if (typeof auth === 'string' && auth.startsWith('Bearer ')) {
    const token = auth.slice('Bearer '.length).trim();
    if (secret) {
      try {
        const payload = jwt.verify(token, secret, {
          algorithms: ['HS256'],
        }) as { sub?: string };
        return typeof payload.sub === 'string' ? payload.sub : null;
      } catch {
        return null;
      }
    }
    if (!insecureDevAuth) {
      return null;
    }
    try {
      const payload = jwt.decode(token) as { sub?: string } | null;
      if (payload && typeof payload.sub === 'string') {
        return payload.sub;
      }
    } catch {
      return null;
    }
  }

  if (!insecureDevAuth) {
    return null;
  }
  const headerUid = req.headers?.['x-trace-user-id'];
  if (typeof headerUid === 'string' && headerUid.length > 0) {
    return headerUid;
  }
  return null;
}

let cachedSupabase: SupabaseClient | null = null;

function supabase(): SupabaseClient | null {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    return null;
  }
  if (!cachedSupabase) {
    cachedSupabase = createClient(url, key);
  }
  return cachedSupabase;
}

/**
 * 校验 uid 是否属于 coupleId 对应的情侣空间。
 * 未配置 SUPABASE_URL / SERVICE_ROLE_KEY 时抛错（fail closed）：
 * 缺少这条校验就无法确认 objectKey 前缀归属，放行等于允许对任意情侣目录签名。
 */
export async function authorizeCouple(uid: string, coupleId: string): Promise<boolean> {
  const db = supabase();
  if (!db) {
    throw new Error(
      'SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not configured; cannot verify couple membership',
    );
  }
  const { data, error } = await db
    .from('couples')
    .select('id')
    .eq('id', coupleId)
    .or(`user_a.eq.${uid},user_b.eq.${uid}`)
    .maybeSingle();
  if (error) {
    throw error;
  }
  return data !== null;
}
