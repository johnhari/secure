import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

void main() {
  CategoryAxisController? controller;
  
  // Test setting visibleMinimum and visibleMaximum
  controller?.visibleMinimum = 5.0;
  controller?.visibleMaximum = 15.0;
  
  print('Compiled CategoryAxisController test successfully');
}
