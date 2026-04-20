import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:permission_handler/permission_handler.dart';
import '../data/database_helper.dart';

class FileService {
  /// الحصول على مسار المجلد الخاص والمخفي داخل التطبيق
  /// تم تحسينه ليكون داخل مجلد ملفات التطبيق الخاصة التي لا يصل إليها المعرض
  static Future<String> get _privateMediaFolder async {
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, '.safe_vault');
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    
    // إضافة ملف .nomedia لضمان عدم قيام المعرض بمسح المجلد (أندرويد)
    final noMedia = File(p.join(path, '.nomedia'));
    if (!await noMedia.exists()) {
      await noMedia.create();
    }
    return path;
  }

  /// معالجة وحفظ الملف بضغط فائق (Ultra Compression)
  /// الهدف: 10KB للصورة الواحدة (10,000 صورة = 100MB)
  static Future<bool> processAndSaveMedia(File sourceFile, String type) async {
    try {
      final folderPath = await _privateMediaFolder;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      // نستخدم امتداد مضلل أو بدون امتداد لمنع المعرض من التعرف عليه
      final internalFileName = 'vlt_${timestamp}_${(timestamp % 1000).toString()}.bin';
      final targetPath = p.join(folderPath, internalFileName);

      Uint8List? thumbnailData;
      
      if (type == 'image') {
        // ضغط فائق جداً (Ultra Compression)
        // تقليل الأبعاد والجودة للوصول لحجم ~10-15KB
        final compressedImage = await FlutterImageCompress.compressAndGetFile(
          sourceFile.path,
          targetPath,
          quality: 25, // جودة منخفضة جداً للوصول للحجم المطلوب
          minWidth: 800, // تصغير الأبعاد لتوفير المساحة
          minHeight: 800,
          format: CompressFormat.webp,
        );

        if (compressedImage == null) {
          await sourceFile.copy(targetPath);
        }

        // صورة مصغرة مجهرية لقاعدة البيانات (أقل من 2KB)
        thumbnailData = await FlutterImageCompress.compressWithList(
          await sourceFile.readAsBytes(),
          minHeight: 60,
          minWidth: 60,
          quality: 15,
          format: CompressFormat.webp,
        );
      } else {
        // للفيديوهات: نسخ الملف حالياً
        // ملاحظة: ضغط الفيديو يتطلب مكتبات ثقيلة مثل ffmpeg_kit_flutter
        await sourceFile.copy(targetPath);
      }

      await DatabaseHelper.instance.insertMedia({
        'file_name': p.basename(sourceFile.path),
        'internal_path': internalFileName,
        'thumbnail_data': thumbnailData,
        'type': type,
        'created_at': DateTime.now().toIso8601String(),
        'original_path': sourceFile.path,
      });

      return true;
    } catch (e) {
      debugPrint('Error processing media: $e');
      return false;
    }
  }

  /// الحصول على الملف الأصلي من المجلد الخاص
  static Future<File?> getMediaFile(String internalFileName) async {
    try {
      final folderPath = await _privateMediaFolder;
      final file = File(p.join(folderPath, internalFileName));
      if (await file.exists()) {
        return file;
      }
      return null;
    } catch (e) {
      debugPrint('Error getting media file: $e');
      return null;
    }
  }

  /// تنزيل الملف تلقائياً إلى مجلد Downloads
  static Future<String?> downloadToPublicFolder(String internalFileName, String originalName) async {
    try {
      // طلب صلاحيات التخزين
      if (Platform.isAndroid) {
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          status = await Permission.storage.request();
          if (!status.isGranted) return 'permission_denied';
        }
      }

      final sourceFile = await getMediaFile(internalFileName);
      if (sourceFile == null) return 'file_not_found';

      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
      } else {
        downloadsDir = await getDownloadsDirectory();
      }

      if (downloadsDir == null || !await downloadsDir.exists()) {
        downloadsDir = await getExternalStorageDirectory();
      }

      if (downloadsDir != null) {
        final targetPath = p.join(downloadsDir.path, originalName);
        await sourceFile.copy(targetPath);
        return targetPath;
      }
      return 'path_not_found';
    } catch (e) {
      debugPrint('Error downloading: $e');
      return 'error';
    }
  }

  /// حذف الملف
  static Future<void> deleteMedia(int id, String internalFileName) async {
    try {
      final folderPath = await _privateMediaFolder;
      final file = File(p.join(folderPath, internalFileName));
      if (await file.exists()) {
        await file.delete();
      }
      await DatabaseHelper.instance.deleteMedia(id);
    } catch (e) {
      debugPrint('Error deleting media: $e');
    }
  }
}
