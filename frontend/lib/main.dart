import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';

void main() => runApp(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(),
    home: HoneypotDashboard(),
  ),
);

class HoneypotDashboard extends StatefulWidget {
  @override
  _HoneypotDashboardState createState() => _HoneypotDashboardState();
}

class _HoneypotDashboardState extends State<HoneypotDashboard> {
  List logs = [];
  bool isChartVisible = true;

  // 1. Fetch logs from FastAPI (now connected to MongoDB)
  Future<void> fetchLogs() async {
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:8000/logs'));
      if (response.statusCode == 200) {
        setState(() {
          logs = json.decode(response.body);
        });
      }
    } catch (e) {
      debugPrint("API Error: $e");
    }
  }

  // 2. Active Defense: Block an IP Address
  Future<void> blockIP(String ip) async {
    try {
      // This sends the block command to your FastAPI cloud-synced route
      final response = await http.post(
        Uri.parse('http://127.0.0.1:8000/block/$ip'),
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("🛡️ IP $ip blacklisted in the Cloud!"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      debugPrint("Network Error: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    fetchLogs();
    // Auto-refresh the dashboard every 3 seconds
    Stream.periodic(Duration(seconds: 3)).listen((_) => fetchLogs());
  }

  // Logic to calculate chart sections based on attack types
  List<PieChartSectionData> getSections() {
    int brute = logs.where((l) => l['attack_type'] == "Brute Force").length;
    int scanning = logs.where((l) => l['attack_type'] == "Scanning").length;
    int bot = logs.where((l) => l['attack_type'] == "Bot Injection").length;

    return [
      PieChartSectionData(
        color: Colors.red,
        value: brute.toDouble(),
        title: brute > 0 ? 'Brute' : '',
        radius: 50,
      ),
      PieChartSectionData(
        color: Colors.green,
        value: scanning.toDouble(),
        title: scanning > 0 ? 'Scan' : '',
        radius: 50,
      ),
      PieChartSectionData(
        color: Colors.orange,
        value: bot.toDouble(),
        title: bot > 0 ? 'Bot' : '',
        radius: 50,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("🕵️ AI HONEYPOT MONITOR"),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: Icon(isChartVisible ? Icons.visibility_off : Icons.pie_chart),
            onPressed: () => setState(() => isChartVisible = !isChartVisible),
          ),
          IconButton(icon: Icon(Icons.refresh), onPressed: fetchLogs),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: fetchLogs, // Manual pull-to-refresh
        child: Column(
          children: [
            if (isChartVisible && logs.isNotEmpty)
              Container(
                height: 200,
                padding: EdgeInsets.all(20),
                child: PieChart(
                  PieChartData(sections: getSections(), centerSpaceRadius: 40),
                ),
              ),
            Expanded(
              child: logs.isEmpty
                  ? Center(child: Text("Waiting for threats..."))
                  : ListView.builder(
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final threat = logs[index];
                        final isHigh = threat['threat_level'] == "High";
                        final isAdmin = threat['username'] == "janar_admin";

                        return Card(
                          margin: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          color: isAdmin
                              ? Colors.blue.withOpacity(0.1)
                              : (isHigh
                                    ? Colors.red.withOpacity(0.1)
                                    : Colors.grey[900]),
                          child: ListTile(
                            leading: Icon(
                              isAdmin
                                  ? Icons.verified_user
                                  : (isHigh ? Icons.warning : Icons.radar),
                              color: isAdmin
                                  ? Colors.blue
                                  : (isHigh ? Colors.red : Colors.green),
                            ),
                            title: Text(
                              "${threat['attack_type']} from ${threat['ip']}",
                            ),
                            subtitle: Text(
                              "User: ${threat['username']} | ${threat['timestamp']}\n📍 ${threat['location']}",
                            ),
                            isThreeLine: true,
                            trailing: isAdmin
                                ? Icon(Icons.check_circle, color: Colors.blue)
                                : IconButton(
                                    icon: Icon(
                                      Icons.block,
                                      color: Colors.redAccent,
                                    ),
                                    onPressed: () => blockIP(
                                      threat['ip'],
                                    ), // Active Defense Trigger
                                  ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
