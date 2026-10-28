/**
 * 存储适配器抽象接口。
 * 所有厂商实现必须满足同一套方法，客户端与上层业务完全不感知具体厂商。
 */
export interface StorageProvider {
  /** 获取 PUT 上传预签名 URL */
  getUploadUrl(key: string, expireSeconds: number): Promise<string>;
  /** 获取 GET 下载预签名 URL */
  getDownloadUrl(key: string, expireSeconds: number): Promise<string>;
  /** 删除云端文件 */
  delete(key: string): Promise<void>;
}

/** 读取必填环境变量，缺失时抛错 */
export function requiredEnv(name: string): string {
  const v = process.env[name];
  if (!v) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return v;
}
