# How to automatically store images on AWS S3?

This cookbook shows you how to configure Sylius to automatically store LiipImagine processed images on AWS S3 instead of the local filesystem. This is essential for production deployments, especially when using multiple servers or containers.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [AWS S3 Setup](#aws-s3-setup)
3. [Symfony Configuration](#symfony-configuration)
4. [LiipImagine Configuration](#liipimaginebundle-configuration)
5. [Testing the Configuration](#testing-the-configuration)
6. [Troubleshooting](#troubleshooting)
7. [Production Considerations](#production-considerations)

## Prerequisites

- A working Sylius installation
- An AWS account with S3 access
- Basic knowledge of Symfony configuration
- AWS CLI installed (for testing)

## AWS S3 Setup

### 1. Create an S3 Bucket

```bash
# Create a bucket (replace with your desired name and region)
aws s3 mb s3://your-sylius-media --region eu-west-3
```

### 2. Configure IAM User

Create an IAM user with the following policy for your S3 bucket:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:PutObjectAcl"
            ],
            "Resource": "arn:aws:s3:::your-sylius-media/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": "arn:aws:s3:::your-sylius-media"
        }
    ]
}
```

### 3. Configure Bucket Policy (for public read access)

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::your-sylius-media/media/cache/*"
        }
    ]
}
```

## Symfony Configuration

### 1. Install Required Packages

```bash
composer require league/flysystem-aws-s3-v3
composer require league/flysystem-bundle
```

### 2. Environment Variables

Add these variables to your `.env` file:

```env
# AWS S3 Configuration
AWS_ACCESS_KEY_ID=your_access_key_here
AWS_SECRET_ACCESS_KEY=your_secret_key_here
AWS_DEFAULT_REGION=eu-west-3
AWS_S3_BUCKET=your-sylius-media
```

### 3. AWS Services Configuration

Create `config/services_aws.yaml`:

```yaml
parameters:
    aws.s3.key: "%env(AWS_ACCESS_KEY_ID)%"
    aws.s3.secret: "%env(AWS_SECRET_ACCESS_KEY)%"
    aws.s3.bucket: "%env(AWS_S3_BUCKET)%"
    aws.s3.region: "%env(AWS_DEFAULT_REGION)%"
    aws.s3.version: "2006-03-01"

services:
    # S3 Client for Flysystem
    Aws\S3\S3Client:
        factory: [Aws\S3\S3Client, 'factory']
        arguments:
            -
                version: "%aws.s3.version%"
                region: "%aws.s3.region%"
                credentials:
                    key: "%aws.s3.key%"
                    secret: "%aws.s3.secret%"
        public: true
```

### 4. Flysystem Configuration

Create or update `config/packages/flysystem.yaml`:

```yaml
flysystem:
    storages:
        sylius.storage:
            adapter: 'aws'
            visibility: public
            options:
                client: 'Aws\S3\S3Client'
                bucket: '%env(AWS_S3_BUCKET)%'
                prefix: ''  # Important: empty prefix to avoid double prefixing
                streamReads: true
```

**⚠️ Critical Note**: The `prefix` must be empty (`''`) to avoid path conflicts with LiipImagine's `cache_prefix` configuration.

## LiipImagineBundle Configuration

Update `config/packages/liip_imagine.yaml`:

```yaml
liip_imagine:
    driver: "gd"
    
    # Configure Flysystem loader for S3
    loaders:
        sylius_image:
            flysystem:
                filesystem_service: 'sylius.storage'
    data_loader: sylius_image
    
    # Configure S3 resolver for cache storage
    resolvers:
        flysystem_s3:
            flysystem:
                filesystem_service: 'sylius.storage'
                root_url: 'https://your-sylius-media.s3.eu-west-3.amazonaws.com'
                cache_prefix: 'media/cache'
                visibility: public
    
    # Use S3 resolver for all filter sets
    cache: flysystem_s3
    
    filter_sets:
        # Example configuration for Sylius product filters
        sylius_shop_product_original:
            cache: flysystem_s3
        
        sylius_shop_product_small_thumbnail:
            format: webp
            quality: 80
            filters:
                thumbnail: { size: [150, 112], mode: outbound }
            cache: flysystem_s3
        
        sylius_shop_product_thumbnail:
            format: webp
            quality: 80
            filters:
                thumbnail: { size: [351, 468], mode: outbound }
            cache: flysystem_s3
        
        sylius_shop_product_large_thumbnail:
            format: webp
            quality: 80
            filters:
                thumbnail: { size: [800, 1200], mode: inset }
            cache: flysystem_s3
```

## Testing the Configuration

### 1. Clear Cache

```bash
php bin/console cache:clear
```

### 2. Test AWS Connectivity

```bash
# Test S3 access
aws s3 ls s3://your-sylius-media/

# Test upload capability
echo "test" | aws s3 cp - s3://your-sylius-media/test.txt
aws s3 rm s3://your-sylius-media/test.txt
```

### 3. Test Image Generation

Create a test command to verify image processing:

```php
<?php
// src/Command/TestImageCacheCommand.php

namespace App\Command;

use Liip\ImagineBundle\Imagine\Cache\CacheManager;
use Liip\ImagineBundle\Model\Binary;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;

#[AsCommand(name: 'app:test-image-cache')]
class TestImageCacheCommand extends Command
{
    public function __construct(private CacheManager $cacheManager)
    {
        parent::__construct();
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        // Create a test image
        $img = imagecreate(100, 100);
        $white = imagecolorallocate($img, 255, 255, 255);
        $black = imagecolorallocate($img, 0, 0, 0);
        imagestring($img, 5, 30, 40, 'TEST', $black);
        
        ob_start();
        imagejpeg($img);
        $content = ob_get_clean();
        imagedestroy($img);
        
        $binary = new Binary($content, 'image/jpeg');
        $testPath = 'test/test-image.jpg';
        $filter = 'sylius_shop_product_thumbnail';
        
        // Store the image
        $this->cacheManager->store($binary, $testPath, $filter);
        $output->writeln('✅ Image stored successfully');
        
        // Check if stored
        $isStored = $this->cacheManager->isStored($testPath, $filter);
        $output->writeln($isStored ? '✅ Image verified as stored' : '❌ Image not found');
        
        // Get URL
        $url = $this->cacheManager->resolve($testPath, $filter);
        $output->writeln("📄 Generated URL: $url");
        
        return Command::SUCCESS;
    }
}
```

Run the test:

```bash
php bin/console app:test-image-cache
```

### 4. Test HTTP Access

```bash
# Test generated image URL (replace with your actual URL)
curl -I https://your-sylius-media.s3.eu-west-3.amazonaws.com/media/cache/sylius_shop_product_thumbnail/test/test-image.jpg
```

Expected response: `HTTP/1.1 200 OK`

### 5. Verify S3 Storage

```bash
# Check if files are stored in S3
aws s3 ls s3://your-sylius-media/media/cache/ --recursive
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Double Prefix Problem

**Symptom**: Images stored in `media/media/cache/` instead of `media/cache/`

**Solution**: Ensure Flysystem prefix is empty:
```yaml
# config/packages/flysystem.yaml
flysystem:
    storages:
        sylius.storage:
            options:
                prefix: ''  # Must be empty!
```

#### 2. 403 Forbidden Errors

**Symptom**: Generated URLs return HTTP 403

**Possible causes**:
- Missing bucket policy for public read access
- Incorrect IAM permissions
- Missing `PutObjectAcl` permission

**Solution**: Verify bucket policy and IAM permissions as shown above.

#### 3. Images Not Generated

**Symptom**: `isStored()` returns false after `store()` call

**Debug steps**:
```php
// Add debug logging to verify the storage process
$this->cacheManager->store($binary, $path, $filter);
$exists = $this->cacheManager->isStored($path, $filter);
error_log("Stored: " . ($exists ? 'YES' : 'NO'));
```

#### 4. Source Images Not Found

**Symptom**: `NotLoadableException` when processing images

**Solution**: Ensure source images are accessible. For S3-stored originals, configure the loader correctly:

```yaml
liip_imagine:
    loaders:
        sylius_image:
            flysystem:
                filesystem_service: 'sylius.storage'
```

### Debugging Commands

```bash
# Check Flysystem configuration
php bin/console debug:container sylius.storage

# Test S3 connectivity
aws s3 ls s3://your-bucket-name/

# Verify AWS credentials
aws sts get-caller-identity

# Check generated URLs
php bin/console liip:imagine:cache:resolve path/to/image.jpg filter_name
```

## Production Considerations

### 1. CDN Integration

Consider using CloudFront for better performance:

```yaml
# config/packages/liip_imagine.yaml
liip_imagine:
    resolvers:
        flysystem_s3:
            flysystem:
                root_url: 'https://your-cdn-domain.cloudfront.net'  # Use CDN URL
                # ... other options
```

### 2. Cache Warming

Pre-generate commonly used image sizes using the built-in LiipImagine command:

```bash
# Warm up cache for specific images and filters
php bin/console liip:imagine:cache:resolve path/to/image.jpg filter_name

# Example: warm up cache for a product image with multiple filters
php bin/console liip:imagine:cache:resolve products/ab/cd/image.jpg sylius_shop_product_thumbnail
php bin/console liip:imagine:cache:resolve products/ab/cd/image.jpg sylius_shop_product_large_thumbnail
```

You can also create a custom command to batch process all your product images:

```php
<?php
// src/Command/WarmupImageCacheCommand.php

namespace App\Command;

use Doctrine\ORM\EntityManagerInterface;
use Liip\ImagineBundle\Imagine\Cache\CacheManager;
use Sylius\Component\Core\Model\ProductImageInterface;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;

#[AsCommand(name: 'app:warmup-image-cache')]
class WarmupImageCacheCommand extends Command
{
    private const FILTERS = [
        'sylius_shop_product_thumbnail',
        'sylius_shop_product_large_thumbnail',
        'sylius_shop_product_small_thumbnail'
    ];

    public function __construct(
        private EntityManagerInterface $entityManager,
        private CacheManager $cacheManager
    ) {
        parent::__construct();
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $productImages = $this->entityManager
            ->getRepository(ProductImageInterface::class)
            ->findAll();

        foreach ($productImages as $productImage) {
            $imagePath = $productImage->getPath();
            
            foreach (self::FILTERS as $filter) {
                if (!$this->cacheManager->isStored($imagePath, $filter)) {
                    $this->cacheManager->resolve($imagePath, $filter);
                    $output->writeln("Generated: {$imagePath} with {$filter}");
                }
            }
        }

        return Command::SUCCESS;
    }
}
```

### 3. Monitoring

Monitor S3 costs and usage:
- Set up CloudWatch alarms for unexpected usage
- Use S3 lifecycle policies for old cache cleanup
- Monitor 404 errors for missing images

### 4. Backup Strategy

- Source images should be backed up separately
- Cache images can be regenerated, so backup is optional
- Consider cross-region replication for critical applications

### 5. Performance Optimization

- Use appropriate S3 storage classes
- Enable S3 Transfer Acceleration for global applications
- Configure proper cache headers

## Security Best Practices

1. **Use IAM roles** instead of access keys when possible
2. **Rotate credentials** regularly
3. **Limit bucket permissions** to minimum required
4. **Enable CloudTrail** for audit logging
5. **Use HTTPS** for all image URLs

## Conclusion

This configuration provides a robust solution for storing Sylius images on AWS S3. The key points to remember:

- Empty Flysystem prefix to avoid path conflicts
- Proper IAM permissions for S3 operations
- Public bucket policy for image access
- Comprehensive testing of the complete workflow

With this setup, your Sylius application will automatically store all processed images on S3, providing scalability and reliability for production environments.