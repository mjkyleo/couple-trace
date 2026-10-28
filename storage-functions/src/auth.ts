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
 * 从请求中解析用户 id：
 * 1) Authorization: Bearer <JWT> → payload.sub
 * 2) X-Trace-User-Id 头（仅本地开发/测试）
 * 返回 null 表示未认证。
 * 注意：生产环境建议由 BaaS 平台中间件完成 JWT 签名校验，此处仅解码取 sub。
 */
export function resolveUid(req: {
  headers?: Record<string, string | string[] | undefined>;
}): string | null {
  const auth = req.headers?.['authorization'];
  if (typeof auth === 'string' && auth.startsWith('Bearer ')) {
    const token = auth.slice('Bearer '.length).trim();
    try {
      const payload = jwt.decode(token) as { sub?: string } | null;
      if (payload && typeof payload.sub === 'string') {
        return payload.sub;
      }
    } catch {
      return null;
    }
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
 * 未配置 SUPABASE_URL / SERVICE_ROLE_KEY 时返回 true（跳过，仅限本地开发）。
 */
export async function authorizeCouple(uid: string, coupleId: string): Promise<boolean> {
  const db = supabase();
  if (!db) {
    return true;
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
