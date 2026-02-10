"""
Data Quality Validation Engine
Executes YAML-defined rules and generates validation reports
"""

import pandas as pd
import yaml
from pathlib import Path
from datetime import datetime
import argparse
from collections import defaultdict


class DataQualityChecker:
    """Execute data quality rules against manufacturing data"""
    
    def __init__(self, rules_path, data_dir):
        self.rules_path = Path(rules_path)
        self.data_dir = Path(data_dir)
        self.rules = self._load_rules()
        self.results = defaultdict(list)
        
    def _load_rules(self):
        """Load DQ rules from YAML"""
        with open(self.rules_path, 'r') as f:
            config = yaml.safe_load(f)
        return config['rules']
    
    def _load_data(self, layer):
        """Load data from specified layer"""
        layer_dir = self.data_dir / layer
        
        data = {}
        if layer_dir.exists():
            for csv_file in layer_dir.glob('*.csv'):
                table_name = csv_file.stem
                data[table_name] = pd.read_csv(csv_file)
                print(f"  Loaded {table_name}: {len(data[table_name]):,} rows")
        
        return data
    
    def _execute_pandas_check(self, rule, data):
        """
        Execute DQ rule using pandas (simplified SQL-to-pandas translation)
        In production, this would use actual SQL against a database
        """
        try:
            # This is a simplified implementation
            # In production, you'd execute actual SQL queries
            
            violations = 0
            violation_details = []
            
            # Map SQL table names to loaded dataframes
            # This is a placeholder - real implementation would parse SQL
            
            if rule['category'] == 'REFERENTIAL_INTEGRITY':
                if 'wafer_tests' in rule['check_sql'] and 'wafer_batches' in rule['check_sql']:
                    if 'wafer_tests' in data and 'wafer_batches' in data:
                        # Check wafer-to-batch integrity
                        tests = data['test_results']
                        batches = data['wafer_batches']
                        
                        merged = tests.merge(batches, on='batch_id', how='left', indicator=True)
                        violations = len(merged[merged['_merge'] == 'left_only'])
                        violation_details = merged[merged['_merge'] == 'left_only']['batch_id'].unique().tolist()[:10]
            
            elif rule['category'] == 'RANGE':
                if 'yield_pct' in rule['check_sql']:
                    # Check yield percentage bounds
                    if 'test_results' in data:
                        tests = data['test_results']
                        # Calculate batch-level yield
                        batch_yield = tests.groupby('batch_id').agg({
                            'pass_fail': lambda x: (x == 'PASS').sum() / len(x) * 100
                        }).reset_index()
                        batch_yield.columns = ['batch_id', 'yield_pct']
                        
                        invalid_yield = batch_yield[(batch_yield['yield_pct'] < 0) | (batch_yield['yield_pct'] > 100)]
                        violations = len(invalid_yield)
                        violation_details = invalid_yield['batch_id'].tolist()[:10]
                
                elif 'defect_density' in rule['check_sql']:
                    if 'test_results' in data:
                        tests = data['test_results']
                        invalid = tests[tests['defect_density'] < 0]
                        violations = len(invalid)
                        violation_details = invalid['wafer_id'].tolist()[:10]
                
                elif 'temperature' in rule['check_sql']:
                    if 'equipment_logs' in data:
                        logs = data['equipment_logs']
                        invalid = logs[(logs['temperature_c'] < -50) | (logs['temperature_c'] > 500)]
                        violations = len(invalid)
                        violation_details = invalid['equipment_id'].unique().tolist()[:10]
                
                elif 'pressure' in rule['check_sql']:
                    if 'equipment_logs' in data:
                        logs = data['equipment_logs']
                        invalid = logs[(logs['pressure_torr'] < 0.001) | (logs['pressure_torr'] > 1000)]
                        violations = len(invalid)
            
            elif rule['category'] == 'COMPLETENESS':
                if 'wafer_id' in rule['check_sql']:
                    if 'test_results' in data:
                        tests = data['test_results']
                        violations = tests['wafer_id'].isna().sum() + (tests['wafer_id'] == '').sum()
                
                elif 'equipment_id' in rule['check_sql']:
                    if 'equipment_logs' in data:
                        logs = data['equipment_logs']
                        violations = logs['equipment_id'].isna().sum() + (logs['equipment_id'] == '').sum()
                
                elif 'pass_fail' in rule['check_sql']:
                    if 'test_results' in data:
                        tests = data['test_results']
                        violations = tests['pass_fail'].isna().sum()
                        violations += len(tests[~tests['pass_fail'].isin(['PASS', 'FAIL'])])
            
            elif rule['category'] == 'UNIQUENESS':
                if 'wafer_id' in rule['check_sql'] and 'batch_id' in rule['check_sql']:
                    if 'test_results' in data:
                        tests = data['test_results']
                        duplicates = tests.groupby(['batch_id', 'wafer_id']).size().reset_index(name='count')
                        duplicates = duplicates[duplicates['count'] > 1]
                        violations = len(duplicates)
                        violation_details = duplicates['wafer_id'].tolist()[:10]
            
            elif rule['category'] == 'TEMPORAL':
                if 'test_results' in data and 'Process Step Sequence' in rule['name']:
                    tests = data['test_results']
                    # Check if process steps are in order
                    tests_sorted = tests.sort_values(['batch_id', 'process_step_id'])
                    tests_sorted['prev_time'] = tests_sorted.groupby('batch_id')['start_time'].shift(1)
                    tests_sorted['start_time'] = pd.to_datetime(tests_sorted['start_time'])
                    tests_sorted['prev_time'] = pd.to_datetime(tests_sorted['prev_time'])
                    
                    invalid = tests_sorted[tests_sorted['start_time'] < tests_sorted['prev_time']].dropna()
                    violations = len(invalid)
                    violation_details = invalid['batch_id'].unique().tolist()[:10]
            
            return violations, violation_details
            
        except Exception as e:
            print(f"  ⚠️  Error executing rule {rule['rule_id']}: {str(e)}")
            return -1, [f"Error: {str(e)}"]
    
    def check_rule(self, rule, data):
        """Execute a single DQ rule"""
        violations, details = self._execute_pandas_check(rule, data)
        
        # Determine pass/fail based on threshold
        threshold = rule.get('threshold', 0)
        
        if violations == -1:
            status = 'ERROR'
        elif violations <= threshold:
            status = 'PASS'
        elif rule['severity'] == 'CRITICAL':
            status = 'FAIL'
        elif rule['severity'] == 'HIGH':
            status = 'FAIL'
        elif rule['severity'] == 'MEDIUM':
            status = 'WARNING'
        else:
            status = 'WARNING'
        
        result = {
            'rule_id': rule['rule_id'],
            'rule_name': rule['name'],
            'category': rule['category'],
            'severity': rule['severity'],
            'status': status,
            'violations': violations,
            'threshold': threshold,
            'impact': rule.get('impact', 'N/A'),
            'details': details[:5] if details else []  # Limit to 5 examples
        }
        
        return result
    
    def run_checks(self, layer='raw'):
        """Execute all DQ rules for a specific layer"""
        print(f"\n{'='*70}")
        print(f"Running Data Quality Checks - Layer: {layer}")
        print(f"{'='*70}\n")
        
        # Load data
        print(f"Loading data from {layer} layer...")
        data = self._load_data(layer)
        
        if not data:
            print(f"❌ No data found in {layer} layer")
            return
        
        print(f"✓ Loaded {len(data)} tables\n")
        
        # Execute rules
        print("Executing validation rules...\n")
        
        results = []
        for rule in self.rules:
            if layer in rule.get('layer', 'staging'):
                print(f"  [{rule['rule_id']}] {rule['name']}...", end=' ')
                result = self.check_rule(rule, data)
                results.append(result)
                
                # Print result
                if result['status'] == 'PASS':
                    print("✅ PASS")
                elif result['status'] == 'WARNING':
                    print(f"⚠️  WARNING ({result['violations']} violations)")
                elif result['status'] == 'FAIL':
                    print(f"❌ FAIL ({result['violations']} violations)")
                else:
                    print("⚡ ERROR")
        
        self.results[layer] = results
        
        # Print summary
        self._print_summary(results)
        
        return results
    
    def _print_summary(self, results):
        """Print DQ check summary"""
        print(f"\n{'='*70}")
        print("Data Quality Summary")
        print(f"{'='*70}\n")
        
        passed = len([r for r in results if r['status'] == 'PASS'])
        warnings = len([r for r in results if r['status'] == 'WARNING'])
        failed = len([r for r in results if r['status'] == 'FAIL'])
        errors = len([r for r in results if r['status'] == 'ERROR'])
        
        print(f"✅ Passed:   {passed:3d}")
        print(f"⚠️  Warnings: {warnings:3d}")
        print(f"❌ Failed:   {failed:3d}")
        print(f"⚡ Errors:   {errors:3d}")
        print(f"{'─'*70}")
        print(f"   Total:    {len(results):3d}\n")
        
        # Show failures and warnings
        if failed > 0:
            print("CRITICAL FAILURES:")
            print(f"{'─'*70}")
            for r in [x for x in results if x['status'] == 'FAIL']:
                print(f"\n[{r['rule_id']}] {r['rule_name']} - {r['severity']}")
                print(f"  Violations: {r['violations']} (threshold: {r['threshold']})")
                print(f"  Impact: {r['impact']}")
                if r['details']:
                    print(f"  Examples: {', '.join(map(str, r['details'][:3]))}")
        
        if warnings > 0:
            print(f"\n{'─'*70}")
            print("WARNINGS:")
            print(f"{'─'*70}")
            for r in [x for x in results if x['status'] == 'WARNING']:
                print(f"\n[{r['rule_id']}] {r['rule_name']}")
                print(f"  Violations: {r['violations']} (threshold: {r['threshold']})")
                print(f"  Impact: {r['impact']}")
        
        print(f"\n{'='*70}\n")
    
    def generate_report(self, output_path='dq/dq_report.md'):
        """Generate markdown DQ report"""
        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(output_path, 'w') as f:
            f.write("# Data Quality Validation Report\n\n")
            f.write(f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
            f.write(f"**Data Directory:** {self.data_dir}\n\n")
            f.write("---\n\n")
            
            for layer, results in self.results.items():
                f.write(f"## Layer: {layer}\n\n")
                
                # Summary table
                passed = len([r for r in results if r['status'] == 'PASS'])
                warnings = len([r for r in results if r['status'] == 'WARNING'])
                failed = len([r for r in results if r['status'] == 'FAIL'])
                
                f.write(f"| Status | Count |\n")
                f.write(f"|--------|-------|\n")
                f.write(f"| ✅ Passed | {passed} |\n")
                f.write(f"| ⚠️ Warnings | {warnings} |\n")
                f.write(f"| ❌ Failed | {failed} |\n\n")
                
                # Detailed results
                f.write("### Detailed Results\n\n")
                
                for r in results:
                    status_icon = {
                        'PASS': '✅',
                        'WARNING': '⚠️',
                        'FAIL': '❌',
                        'ERROR': '⚡'
                    }.get(r['status'], '❓')
                    
                    f.write(f"#### {status_icon} [{r['rule_id']}] {r['rule_name']}\n\n")
                    f.write(f"- **Category:** {r['category']}\n")
                    f.write(f"- **Severity:** {r['severity']}\n")
                    f.write(f"- **Status:** {r['status']}\n")
                    f.write(f"- **Violations:** {r['violations']} (threshold: {r['threshold']})\n")
                    f.write(f"- **Impact:** {r['impact']}\n")
                    
                    if r['details']:
                        f.write(f"- **Examples:** {', '.join(map(str, r['details']))}\n")
                    
                    f.write("\n")
                
                f.write("---\n\n")
        
        print(f"✅ DQ Report generated: {output_path}\n")


def main():
    parser = argparse.ArgumentParser(description='Run data quality checks')
    parser.add_argument('--rules', type=str, default='dq/rules.yml',
                        help='Path to DQ rules YAML file')
    parser.add_argument('--data-dir', type=str, default='data',
                        help='Root data directory')
    parser.add_argument('--layer', type=str, default='raw',
                        choices=['raw', 'staging', 'curated'],
                        help='Data layer to validate')
    parser.add_argument('--report', action='store_true',
                        help='Generate markdown report')
    
    args = parser.parse_args()
    
    checker = DataQualityChecker(args.rules, args.data_dir)
    checker.run_checks(layer=args.layer)
    
    if args.report:
        checker.generate_report()


if __name__ == '__main__':
    main()
