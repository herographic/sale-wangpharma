// lib/screens/sales_summary_screen.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/customer.dart';
import 'package:salewang/models/sale_support_customer.dart';
import 'package:salewang/utils/launcher_helper.dart';
import 'package:salewang/models/member.dart' as member_model;
import 'package:salewang/screens/customer_detail_screen.dart';

enum SearchType { name, code, salesperson }
enum SalesSortType { currentMonthDesc, previousMonthDesc }

class CustomerSalesData {
  final SaleSupportCustomer customer;
  final Customer? firestoreCustomer;
  final double currentMonthSales;
  final double previousMonthSales;
  final String? routeCode;

  CustomerSalesData({
    required this.customer,
    this.firestoreCustomer,
    required this.currentMonthSales,
    required this.previousMonthSales,
    this.routeCode,
  });
}

class SalesSummaryScreen extends StatefulWidget {
  const SalesSummaryScreen({super.key});

  @override
  State<SalesSummaryScreen> createState() => _SalesSummaryScreenState();
}

class _SalesSummaryScreenState extends State<SalesSummaryScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<CustomerSalesData> _allCustomerData = [];
  List<CustomerSalesData> _searchResults = [];
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _debounce;
  String _statusMessage = 'กำลังโหลดข้อมูลลูกค้า...';
  
  SearchType _searchType = SearchType.name;
  String? _selectedRouteCode;
  String? _selectedPriceCode;
  SalesSortType _salesSortType = SalesSortType.currentMonthDesc;

  final Map<String, String> routeShortcuts = {
    'อ.หาดใหญ่1': 'L1-1', 'เมืองสงขลา': 'L1-2', 'สะเดา': 'L1-3', 'ปัตตานี': 'L2', 'สตูล': 'L3',
    'พัทลุง': 'L4', 'นราธิวาส': 'L5-1', 'สุไหงโกลก': 'L5-2', 'ยะลา': 'L6', 'เบตง': 'L7',
    'ตรัง': 'L9', 'นครศรีฯ': 'L10', 'วังเภสัช': 'Office', 'อื่นๆ': 'R-00', 'สทิงพระ': 'L1-5',
    'ฝากขนส่ง': 'Logistic', 'กระบี่': 'L11', 'ภูเก็ต': 'L12', 'สุราษฎร์ฯ': 'L13', 'พังงา': 'L17',
    'ยาแห้ง': 'L16', 'พัทลุง VIP': 'L4-1', 'เกาะสมุย': 'L18', 'พัทลุง-นคร': 'L19', 'ชุมพร': 'L20',
    'กระบี่-ตรัง': 'L9-11', 'เกาะลันตา': 'L21', 'เกาะพะงัน': 'L22', 'อ.หาดใหญ่2': 'L23',
  };

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadAllDataFromCache();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _applyFiltersAndSort();
    });
  }

  Future<void> _loadAllDataFromCache() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      
      final salesFuture = firestore.collection('api_sale_support_cache').get();
      final routesFuture = firestore.collection('api_member_route_cache').get();
      final customersFuture = firestore.collection('customers').get();

      final responses = await Future.wait([salesFuture, routesFuture, customersFuture]);
      
      final salesSnapshot = responses[0];
      final routesSnapshot = responses[1];
      final customersSnapshot = responses[2];

      if (salesSnapshot.docs.isEmpty) {
        throw Exception('Cache is empty. Please sync data first.');
      }

      final routeDataMap = { for (var doc in routesSnapshot.docs) doc.id.replaceAll('-', '/'): doc.data()['route_code'] };
      final firestoreCustomerMap = { for (var doc in customersSnapshot.docs) doc.data()['รหัสลูกค้า']: Customer.fromFirestore(doc) };

      List<CustomerSalesData> processedData = salesSnapshot.docs.map((doc) {
        final customer = SaleSupportCustomer.fromFirestore(doc);
        final now = DateTime.now();
        double currentMonthSales = 0.0;
        double previousMonthSales = 0.0;
        final previousMonthDate = DateTime(now.year, now.month - 1, 1);

        for (var order in customer.order) {
          final orderDate = DateTime.tryParse(order.date ?? '');
          if (orderDate != null) {
            final price = double.tryParse(order.price?.replaceAll(',', '') ?? '0') ?? 0.0;
            if (orderDate.year == now.year && orderDate.month == now.month) {
              currentMonthSales += price;
            } else if (orderDate.year == previousMonthDate.year && orderDate.month == previousMonthDate.month) {
              previousMonthSales += price;
            }
          }
        }
        
        final customerCode = customer.memCode ?? '';
        return CustomerSalesData(
          customer: customer,
          firestoreCustomer: firestoreCustomerMap[customerCode],
          currentMonthSales: currentMonthSales,
          previousMonthSales: previousMonthSales,
          routeCode: routeDataMap[customerCode],
        );
      }).toList();

      if (mounted) {
        setState(() {
          _allCustomerData = processedData;
          _statusMessage = 'ใช้ตัวกรองด้านบนเพื่อค้นหาลูกค้า';
          _applyFiltersAndSort();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFiltersAndSort() {
    List<CustomerSalesData> filteredList = List.from(_allCustomerData);
    final query = _searchController.text.trim().toLowerCase();

    if (query.isNotEmpty) {
      filteredList = filteredList.where((data) {
        final customer = data.customer;
        switch (_searchType) {
          case SearchType.name:
            return customer.memName?.toLowerCase().contains(query) ?? false;
          case SearchType.code:
            return customer.memCode?.toLowerCase().contains(query) ?? false;
          case SearchType.salesperson:
            return customer.memSale?.toLowerCase().contains(query) ?? false;
        }
      }).toList();
    }

    if (_selectedRouteCode != null) {
      filteredList = filteredList.where((data) => data.routeCode == _selectedRouteCode).toList();
    }

    if (_selectedPriceCode != null) {
      filteredList = filteredList.where((data) => data.customer.memPrice == _selectedPriceCode).toList();
    }

    if (query.isEmpty) {
      filteredList.removeWhere((data) => data.currentMonthSales <= 0 && data.previousMonthSales <= 0);
    }
    
    _sortResults(filteredList);

    setState(() {
      _searchResults = filteredList;
      if (_searchResults.isEmpty) {
        _statusMessage = 'ไม่พบข้อมูลลูกค้าที่ตรงกับเงื่อนไข';
      }
    });
  }

  void _sortResults(List<CustomerSalesData> dataToSort) {
    dataToSort.sort((a, b) {
      final aHasSales = a.currentMonthSales > 0 || a.previousMonthSales > 0;
      final bHasSales = b.currentMonthSales > 0 || b.previousMonthSales > 0;

      if (aHasSales && !bHasSales) return -1;
      if (!aHasSales && bHasSales) return 1;

      if (_salesSortType == SalesSortType.currentMonthDesc) {
        int compare = b.currentMonthSales.compareTo(a.currentMonthSales);
        if (compare == 0) {
          return b.previousMonthSales.compareTo(a.previousMonthSales);
        }
        return compare;
      } else {
        int compare = b.previousMonthSales.compareTo(a.previousMonthSales);
        if (compare == 0) {
           return b.currentMonthSales.compareTo(a.currentMonthSales);
        }
        return compare;
      }
    });
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _selectedRouteCode = null;
      _selectedPriceCode = null;
      _applyFiltersAndSort();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0052D4), Color(0xFF4364F7), Color(0xFF6FB1FC)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('ค้นหารายชื่อลูกค้า', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            _buildSearchPanel(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Card(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'พิมพ์คำค้นหา...',
                        border: InputBorder.none,
                        prefixIcon: const Icon(Icons.search),
                      ),
                    ),
                  ),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<SearchType>(
                      value: _searchType,
                      items: const [
                        DropdownMenuItem(value: SearchType.name, child: Text("ชื่อ")),
                        DropdownMenuItem(value: SearchType.code, child: Text("รหัส")),
                        DropdownMenuItem(value: SearchType.salesperson, child: Text("พนักงาน")),
                      ],
                      onChanged: (SearchType? newValue) {
                        if (newValue != null) {
                          setState(() => _searchType = newValue);
                          _applyFiltersAndSort();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedRouteCode,
                        hint: const Text("เลือกเส้นทาง"),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<String>(value: null, child: Text("ทุกเส้นทาง")),
                          ...routeShortcuts.entries.map((entry) {
                            return DropdownMenuItem(
                              value: entry.value,
                              child: Text(entry.key, overflow: TextOverflow.ellipsis),
                            );
                          }),
                        ],
                        onChanged: (String? newValue) {
                          setState(() => _selectedRouteCode = newValue);
                          _applyFiltersAndSort();
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedPriceCode,
                        hint: const Text("เลือกระดับราคา"),
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem<String>(value: null, child: Text("ทุกระดับราคา")),
                          DropdownMenuItem(value: 'A', child: Text("ราคา A")),
                          DropdownMenuItem(value: 'B', child: Text("ราคา B")),
                          DropdownMenuItem(value: 'C', child: Text("ราคา C")),
                        ],
                        onChanged: (String? newValue) {
                          setState(() => _selectedPriceCode = newValue);
                          _applyFiltersAndSort();
                        },
                      ),
                    ),
                  ),
                   IconButton(
                    icon: const Icon(Icons.cancel_rounded, color: Colors.grey),
                    tooltip: 'ล้างตัวกรอง',
                    onPressed: _clearFilters,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<SalesSortType>(
                  value: _salesSortType,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: SalesSortType.currentMonthDesc, child: Text("เรียงตามยอดเดือนปัจจุบันสูงสุด")),
                    DropdownMenuItem(value: SalesSortType.previousMonthDesc, child: Text("เรียงตามยอดเดือนก่อนสูงสุด")),
                  ],
                  onChanged: (SalesSortType? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _salesSortType = newValue;
                        _applyFiltersAndSort();
                      });
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.white)));
    }
    if (_searchResults.isEmpty) {
      return Center(child: Text(_statusMessage, style: const TextStyle(color: Colors.white70)));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final customerData = _searchResults[index];
        return _CustomerInfoCard(customerData: customerData);
      },
    );
  }
}

class _CustomerInfoCard extends StatelessWidget {
  final CustomerSalesData customerData;

  const _CustomerInfoCard({required this.customerData});

  @override
  Widget build(BuildContext context) {
    final customer = customerData.customer;
    final currencyFormat = NumberFormat("#,##0.00", "en_US");
    final balance = double.tryParse(customer.memBalance?.replaceAll(',', '') ?? '0') ?? 0.0;
    
    final hasPendingOrder = customer.statusOrder.any((s) => s.status == 'กำลังเปิดบิล');
    final cardColor = hasPendingOrder ? Colors.amber.shade50 : Colors.white;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: cardColor,
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.grey.shade200,
                child: ClipOval(
                  child: (customer.memImg != null && customer.memImg!.isNotEmpty && !customer.memImg!.endsWith('Akitokung/'))
                      ? Image.network(
                          customer.memImg!,
                          fit: BoxFit.cover,
                          width: 56,
                          height: 56,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(Icons.store, size: 28, color: Colors.grey);
                          },
                        )   
                      : const Icon(Icons.store, size: 28, color: Colors.grey),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customer.memName ?? 'N/A', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('รหัส: ${customer.memCode ?? '-'} | ราคา: ${customer.memPrice ?? '-'} | โดย: ${customer.memSale ?? '-'}', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                    _buildMonthlySalesSummary(context, customerData.previousMonthSales, customerData.currentMonthSales),
                  ],
                ),
              ),
            ],
          ),
          trailing: hasPendingOrder
            ? const Tooltip(
                message: 'มีรายการกำลังเปิดบิล',
                child: Icon(Icons.hourglass_top, color: Colors.orange),
              )
            : const Icon(Icons.keyboard_arrow_down),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                children: [
                  const Divider(height: 1),
                  _buildInfoRow(context, Icons.location_on_outlined, "ที่อยู่:", customer.memAddress, maxLines: 2),
                  _buildInfoRow(context, Icons.phone_outlined, "เบอร์โทร:", customer.memPhone, isCallable: true),
                  _buildInfoRow(context, Icons.calendar_today_outlined, "ขายล่าสุด:", customer.memLastsale),
                  _buildInfoRow(context, Icons.payment_outlined, "ชำระล่าสุด:", customer.memLastpayments),
                  _buildInfoRow(context, Icons.account_balance_wallet_outlined, "ยอดค้าง:", currencyFormat.format(balance), valueColor: balance > 0 ? Colors.red : Colors.green),
                  if (customer.order.isNotEmpty)
                    _buildOrderHistory(context, customer.order),
                  if (customer.statusOrder.isNotEmpty)
                    _buildOrderStatusTimeline(context, customer.statusOrder),
                ],
              ),
            )
          ],
        ),
    );
  }

  Widget _buildMonthlySalesSummary(BuildContext context, double previousMonthSales, double currentMonthSales) {
    final currencyFormat = NumberFormat("#,##0", "en_US");
    final difference = currentMonthSales - previousMonthSales;
    
    double percentage = 0;
    if (previousMonthSales > 0) {
      percentage = (difference / previousMonthSales) * 100;
    } else if (currentMonthSales > 0) {
      percentage = 100.0;
    }

    final bool isUp = difference >= 0;
    final Color progressColor = isUp ? Colors.green : Colors.red;
    final String differenceText = isUp ? '+${currencyFormat.format(difference)}' : currencyFormat.format(difference);
    final String percentageText = isUp ? '+${percentage.toStringAsFixed(1)}%' : '${percentage.toStringAsFixed(1)}%';

    double barPercentage = 0;
    if (previousMonthSales > 0 || currentMonthSales > 0) {
      final totalAbs = previousMonthSales.abs() + currentMonthSales.abs();
      if (totalAbs > 0) {
        barPercentage = currentMonthSales.abs() / totalAbs;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('เดือนก่อน: ${currencyFormat.format(previousMonthSales)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text('เดือนนี้: ${currencyFormat.format(currentMonthSales)}', style: TextStyle(fontSize: 12, color: progressColor, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 22,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: barPercentage.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: progressColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          percentageText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            shadows: [Shadow(color: Colors.black45, blurRadius: 2)],
                          ),
                        ),
                        Text(
                          differenceText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            shadows: [Shadow(color: Colors.black45, blurRadius: 2)],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildOrderHistory(BuildContext context, List<OrderHistory> orders) {
    final currencyFormat = NumberFormat("#,##0.00", "en_US");
    final thaiDateFormat = DateFormat('dd/MM/yy', 'th_TH');
    final recentOrders = orders.take(5).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("ประวัติการซื้อล่าสุด:", style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...recentOrders.map((order) {
            final priceValue = double.tryParse(order.price?.replaceAll(',', '') ?? '0') ?? 0.0;
            final isCreditNote = priceValue < 0;
            final date = DateTime.tryParse(order.date ?? '');
            final formattedDate = date != null ? thaiDateFormat.format(date) : '-';

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: isCreditNote ? Colors.red : Colors.green, width: 3)),
                color: Colors.grey.shade100,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('เลขที่: ${order.bill ?? '-'}', style: const TextStyle(fontSize: 12)),
                        Text('วันที่: $formattedDate', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                  ),
                  Text(
                    currencyFormat.format(priceValue),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isCreditNote ? Colors.red : Colors.black87,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildOrderStatusTimeline(BuildContext context, List<StatusOrder> statuses) {
    final statusesToShow = statuses.take(5).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("สถานะออเดอร์ 5 รายการล่าสุด:", style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...List.generate(statusesToShow.length, (index) {
            return _TimelineTile(
              statusOrder: statusesToShow[index],
              isFirst: index == 0,
              isLast: index == statusesToShow.length - 1,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, IconData icon, String label, String? value, {Color? valueColor, int maxLines = 1, bool isCallable = false}) {
    final displayValue = (value != null && value.isNotEmpty) ? value : '-';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.grey.shade600, size: 16),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              displayValue,
              style: TextStyle(color: valueColor ?? Colors.black87, fontSize: 13),
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if(isCallable)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 24,
                  width: 24,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.chat_bubble_outline, color: Colors.blue.shade700, size: 20),
                    tooltip: 'บันทึกข้อมูลลูกค้า',
                    onPressed: () {
                      if (customerData.firestoreCustomer != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CustomerDetailScreen(customer: customerData.firestoreCustomer!),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('ไม่พบข้อมูลลูกค้าในระบบ (Firestore)')),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 24,
                  width: 24,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.phone_forwarded_outlined, color: Colors.green.shade700, size: 20),
                    tooltip: 'โทรหาลูกค้า',
                    onPressed: () {
                      // --- FIX: Add null check before making a call ---
                      if (customerData.customer.memPhone != null && customerData.customer.memPhone!.isNotEmpty) {
                        final tempMember = member_model.Member(
                          memCode: customerData.customer.memCode,
                          memName: customerData.customer.memName,
                          memTel: customerData.customer.memPhone,
                          empCode: customerData.customer.memSale,
                        );
                        LauncherHelper.makeAndLogApiCall(
                          context: context,
                          phoneNumber: customerData.customer.memPhone!,
                          member: tempMember,
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('ไม่มีเบอร์โทรศัพท์สำหรับลูกค้ารายนี้')),
                        );
                      }
                    },
                  ),
                ),
              ],
            )
        ],
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  final StatusOrder statusOrder;
  final bool isFirst;
  final bool isLast;

  const _TimelineTile({required this.statusOrder, this.isFirst = false, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    String statusText = statusOrder.status ?? 'N/A';
    if (statusOrder.status == 'จัดส่งสำเร็จ' && statusOrder.emp != null && statusOrder.emp!.isNotEmpty) {
      statusText += ' โดย: ${statusOrder.emp}';
    }

    return IntrinsicHeight(
      child: Row(
        children: [
          Column(
            children: [
              Container(
                width: 1,
                height: 4,
                color: isFirst ? Colors.transparent : Colors.grey,
              ),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFirst ? Colors.green : Colors.grey,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.check, size: 12, color: Colors.white),
              ),
              Expanded(
                child: Container(
                  width: 1,
                  color: isLast ? Colors.transparent : Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: TextStyle(
                    fontWeight: isFirst ? FontWeight.bold : FontWeight.normal,
                    color: isFirst ? Colors.green.shade800 : Colors.black87,
                  ),
                ),
                Text(
                  'เลขที่: ${statusOrder.sohRuning ?? '-'}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
