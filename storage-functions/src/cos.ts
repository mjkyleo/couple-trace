import COS from 'cos-nodejs-sdk-v5';
import { StorageProvider, requiredEnv } from './base';

/**
 * 腾讯云 COS 实现。
 * 环境变量：COS_SECRET_ID / COS_SECRET_KEY / COS_BUCKET / COS_REGION
 */
export class CosProvider implements StorageProvider {
  private readonly cos: COS;
  private readonly bucket: string;
  private readonly region: string;

  constructor() {
    this.bucket = requiredEnv('COS_BUCKET');
    this.region = requiredEnv('COS_REGION');
    this.cos = new COS({
      SecretId: requiredEnv('COS_SECRET_ID'),
      SecretKey: requiredEnv('COS_SECRET_KEY'),
    });
  }

  /** COS SDK 的 getObjectUrl 为 callback 风格，包装为 Promise */
  private signUrl(key: string, method: 'PUT' | 'GET', expireSeconds: number): Promise<string> {
    return new Promise((resolve, reject) => {
      this.cos.getObjectUrl(
        {
          Bucket: this.bucket,
          Region: this.region,
          Key: key,
          Method: method,
          Expires: expireSeconds,
        },
        (err, data) => {
          if (err) {
            reject(err);
          } else {
            resolve(data.Url);
          }
        },
      );
    });
  }

  getUploadUrl(key: string, expireSeconds: number): Promise<string> {
    return this.signUrl(key, 'PUT', expireSeconds);
  }

  getDownloadUrl(key: string, expireSeconds: number): Promise<string> {
    return this.signUrl(key, 'GET', expireSeconds);
  }

  async delete(key: string): Promise<void> {
    await this.cos.deleteObject({
      Bucket: this.bucket,
      Region: this.region,
      Key: key,
    });
  }
}
