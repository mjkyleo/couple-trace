import OSS from 'ali-oss';
import { StorageProvider, requiredEnv } from './base';

/**
 * 阿里云 OSS 实现。
 * 环境变量：OSS_ACCESS_KEY / OSS_SECRET / OSS_BUCKET / OSS_REGION
 */
export class OssProvider implements StorageProvider {
  private readonly client: OSS;

  constructor() {
    this.client = new OSS({
      region: requiredEnv('OSS_REGION'),
      accessKeyId: requiredEnv('OSS_ACCESS_KEY'),
      accessKeySecret: requiredEnv('OSS_SECRET'),
      bucket: requiredEnv('OSS_BUCKET'),
    });
  }

  async getUploadUrl(key: string, expireSeconds: number): Promise<string> {
    return this.client.signatureUrl(key, { expires: expireSeconds, method: 'PUT' });
  }

  async getDownloadUrl(key: string, expireSeconds: number): Promise<string> {
    return this.client.signatureUrl(key, { expires: expireSeconds });
  }

  async delete(key: string): Promise<void> {
    await this.client.delete(key);
  }
}
