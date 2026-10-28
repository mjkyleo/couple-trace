import { StorageProvider } from './base';
import { CosProvider } from './cos';
import { OssProvider } from './oss';
import { S3Provider } from './s3';

/**
 * 存储适配器工厂。
 * 通过环境变量 STORAGE_PROVIDER 切换厂商，无需改动任何业务代码。
 * 可选值：cos | oss | s3 | minio
 */
export function createStorageProvider(): StorageProvider {
  const provider = (process.env.STORAGE_PROVIDER || 's3').toLowerCase();
  switch (provider) {
    case 'cos':
      return new CosProvider();
    case 'oss':
      return new OssProvider();
    case 's3':
    case 'minio':
      return new S3Provider();
    default:
      throw new Error(`Unsupported STORAGE_PROVIDER: ${provider}`);
  }
}
