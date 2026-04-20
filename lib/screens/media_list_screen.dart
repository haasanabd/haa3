import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../data/database_helper.dart';
import '../services/file_service.dart';
import '../widgets/video_player_widget.dart';

class MediaListScreen extends StatefulWidget {
  final String type; // 'image' or 'video'
  const MediaListScreen({super.key, required this.type});

  @override
  State<MediaListScreen> createState() => _MediaListScreenState();
}

class _MediaListScreenState extends State<MediaListScreen> {
  List<Map<String, dynamic>> _mediaList = [];
  final Set<int> _selectedIds = {};
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = true;
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    setState(() => _isLoading = true);
    try {
      final data = await DatabaseHelper.instance.queryAllMedia(widget.type);
      setState(() {
        _mediaList = data;
        _isLoading = false;
        _selectedIds.clear();
        _isSelectionMode = false;
      });
    } catch (e) {
      debugPrint('Error loading media: $e');
      setState(() => _isLoading = false);
    }
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
        _isSelectionMode = true;
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedIds.length == _mediaList.length) {
        _selectedIds.clear();
        _isSelectionMode = false;
      } else {
        _selectedIds.clear();
        for (var item in _mediaList) {
          _selectedIds.add(item['id']);
        }
        _isSelectionMode = true;
      }
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف $count من العناصر المختارة نهائياً؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        for (var id in _selectedIds) {
          final item = _mediaList.firstWhere((element) => element['id'] == id);
          await FileService.deleteMedia(id, item['internal_path']);
        }
        _loadMedia();
      } catch (e) {
        debugPrint('Error deleting media: $e');
        _loadMedia();
      }
    }
  }

  /// تنزيل الملفات المختارة مباشرة إلى مجلد التنزيلات
  Future<void> _downloadSelected() async {
    setState(() => _isLoading = true);
    int successCount = 0;
    String? lastPath;

    try {
      for (var id in _selectedIds) {
        final item = _mediaList.firstWhere((element) => element['id'] == id);
        final result = await FileService.downloadToPublicFolder(
          item['internal_path'], 
          item['file_name']
        );
        
        if (result != null && !['error', 'permission_denied', 'file_not_found', 'path_not_found'].contains(result)) {
          successCount++;
          lastPath = result;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successCount > 0 
              ? 'تم تنزيل $successCount ملف إلى مجلد Download' 
              : 'فشل التنزيل، يرجى التحقق من الصلاحيات'),
            action: successCount == 1 ? SnackBarAction(label: 'فتح', onPressed: () {
              // يمكن إضافة كود لفتح الملف هنا
            }) : null,
          )
        );
      }
      
      setState(() {
        _isLoading = false;
        _selectedIds.clear();
        _isSelectionMode = false;
      });
    } catch (e) {
      debugPrint('Error downloading media: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickMultiMedia() async {
    try {
      List<String> paths = [];
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: widget.type == 'image' ? FileType.image : FileType.video,
        allowMultiple: true,
      );

      if (result != null && result.paths.isNotEmpty) {
        paths = result.paths.whereType<String>().toList();
      }
      
      if (paths.isNotEmpty) {
        _showProgressDialog(paths.length);
        int successCount = 0;
        
        for (var path in paths) {
          final success = await FileService.processAndSaveMedia(File(path), widget.type);
          if (success) successCount++;
        }
        
        if (mounted) Navigator.pop(context);
        _loadMedia();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم حفظ $successCount ملف بضغط فائق في الخزنة'))
        );
      }
    } catch (e) {
      debugPrint('Error picking media: $e');
    }
  }

  void _showProgressDialog(int total) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text('جاري ضغط ومعالجة $total ملف...', style: const TextStyle(fontWeight: FontWeight.bold)),
            const Text('يتم الآن تقليل الحجم لأقصى درجة', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.type == 'image' ? 'الخزنة الآمنة للصور' : 'الخزنة الآمنة للفيديوهات';
    
    return Scaffold(
      appBar: AppBar(
        title: Text(_isSelectionMode ? '${_selectedIds.length} مختار' : title),
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.download_for_offline_rounded),
              onPressed: _downloadSelected,
              tooltip: 'تنزيل لمجلد Download',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: _deleteSelected,
              tooltip: 'حذف المختار',
            ),
          ],
          if (_mediaList.isNotEmpty)
            IconButton(
              icon: Icon(_selectedIds.length == _mediaList.length ? Icons.deselect : Icons.select_all),
              onPressed: _selectAll,
              tooltip: 'تحديد الكل',
            ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _mediaList.isEmpty 
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.type == 'image' ? Icons.lock_outline : Icons.video_library_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('الخزنة فارغة حالياً', style: TextStyle(fontSize: 18, color: Colors.grey)),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: _mediaList.length,
              itemBuilder: (context, index) {
                final item = _mediaList[index];
                final id = item['id'];
                final Uint8List? thumbnail = item['thumbnail_data'];
                final isSelected = _selectedIds.contains(id);
                
                return GestureDetector(
                  onLongPress: () => _toggleSelection(id),
                  onTap: () {
                    if (_isSelectionMode) {
                      _toggleSelection(id);
                    } else {
                      _viewMedia(item);
                    }
                  },
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: widget.type == 'image' && thumbnail != null
                            ? Image.memory(thumbnail, fit: BoxFit.cover)
                            : Container(
                                color: Colors.black87,
                                child: Center(
                                  child: Icon(
                                    widget.type == 'image' ? Icons.image : Icons.play_circle_outline, 
                                    color: Colors.white, 
                                    size: 40
                                  ),
                                ),
                              ),
                        ),
                      ),
                      if (isSelected)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue, width: 2),
                            ),
                            child: const Icon(Icons.check_circle, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickMultiMedia,
        backgroundColor: widget.type == 'image' ? Colors.blueAccent : Colors.redAccent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(widget.type == 'image' ? 'إضافة صور' : 'إضافة فيديوهات', style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  Future<void> _viewMedia(Map<String, dynamic> item) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    
    final file = await FileService.getMediaFile(item['internal_path']);
    if (mounted) Navigator.pop(context);

    if (file == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر العثور على الملف')));
      return;
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              iconTheme: const IconThemeData(color: Colors.white),
              title: Text(item['file_name'], style: const TextStyle(color: Colors.white, fontSize: 14)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.download_rounded, color: Colors.white),
                  onPressed: () async {
                    final result = await FileService.downloadToPublicFolder(item['internal_path'], item['file_name']);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(result != null && !['error', 'permission_denied'].contains(result) 
                          ? 'تم التنزيل إلى مجلد Download' 
                          : 'فشل التنزيل'))
                      );
                    }
                  },
                )
              ],
            ),
            body: Center(
              child: widget.type == 'image'
                ? InteractiveViewer(child: Image.file(file))
                : VideoPlayerWidget(file: file),
            ),
          ),
        ),
      );
    }
  }
}
