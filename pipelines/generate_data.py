"""
Semiconductor Manufacturing Data Generator
Simulates realistic equipment logs, wafer batches, test results, and maintenance events
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import argparse
import os
from pathlib import Path

# Set random seed for reproducibility
np.random.seed(42)

class SemiconductorDataGenerator:
    """Generate realistic semiconductor manufacturing data"""
    
    def __init__(self, start_date, days, output_dir):
        self.start_date = pd.to_datetime(start_date)
        self.days = days
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        # Manufacturing constants
        self.EQUIPMENT_TYPES = ['ETCH', 'LITHO', 'IMPLANT', 'CVD', 'PVD', 'CMP', 'TEST']
        self.PROCESS_STEPS = [
            {'step_id': 1, 'name': 'Photolithography', 'equipment_type': 'LITHO', 'duration_min': 45},
            {'step_id': 2, 'name': 'Plasma Etch', 'equipment_type': 'ETCH', 'duration_min': 30},
            {'step_id': 3, 'name': 'Ion Implantation', 'equipment_type': 'IMPLANT', 'duration_min': 60},
            {'step_id': 4, 'name': 'CVD Deposition', 'equipment_type': 'CVD', 'duration_min': 40},
            {'step_id': 5, 'name': 'Chemical Mechanical Polish', 'equipment_type': 'CMP', 'duration_min': 25},
            {'step_id': 6, 'name': 'Electrical Test', 'equipment_type': 'TEST', 'duration_min': 15}
        ]
        self.WAFERS_PER_BATCH = 25
        self.BATCHES_PER_DAY = 20
        
        # Equipment inventory
        self.equipment = self._generate_equipment_inventory()
        
    def _generate_equipment_inventory(self):
        """Create equipment master data"""
        equipment_list = []
        for eq_type in self.EQUIPMENT_TYPES:
            num_tools = np.random.randint(3, 8)  # 3-7 tools per type
            for i in range(num_tools):
                equipment_list.append({
                    'equipment_id': f"{eq_type[:3]}{i+1:03d}",
                    'equipment_type': eq_type,
                    'manufacturer': np.random.choice(['Applied Materials', 'Lam Research', 'ASML', 'KLA']),
                    'install_date': self.start_date - timedelta(days=np.random.randint(365, 1825)),  # 1-5 years old
                    'status': 'ACTIVE'
                })
        return pd.DataFrame(equipment_list)
    
    def generate_equipment_logs(self):
        """Generate equipment sensor logs"""
        print("Generating equipment logs...")
        
        all_logs = []
        current_time = self.start_date
        end_time = self.start_date + timedelta(days=self.days)
        
        # For each equipment, generate status changes and sensor readings
        for _, eq in self.equipment.iterrows():
            eq_time = current_time
            
            # Equipment degradation factor (older equipment has more variability)
            age_days = (current_time - eq['install_date']).days
            degradation_factor = 1 + (age_days / 1825) * 0.1  # 10% degradation over 5 years
            
            while eq_time < end_time:
                # Equipment operates in cycles
                cycle_duration = np.random.randint(60, 240)  # 1-4 hours
                status = np.random.choice(['RUNNING', 'IDLE', 'ALARM', 'DOWN'], p=[0.70, 0.20, 0.08, 0.02])
                
                # Generate sensor readings based on equipment type
                if eq['equipment_type'] == 'ETCH':
                    temperature = np.random.normal(250, 10 * degradation_factor)
                    pressure = np.random.normal(0.1, 0.02 * degradation_factor)
                elif eq['equipment_type'] == 'LITHO':
                    temperature = np.random.normal(23, 2 * degradation_factor)
                    pressure = np.random.normal(1.0, 0.1 * degradation_factor)
                elif eq['equipment_type'] == 'CVD':
                    temperature = np.random.normal(400, 20 * degradation_factor)
                    pressure = np.random.normal(5.0, 0.5 * degradation_factor)
                else:
                    temperature = np.random.normal(100, 15 * degradation_factor)
                    pressure = np.random.normal(1.0, 0.2 * degradation_factor)
                
                all_logs.append({
                    'equipment_id': eq['equipment_id'],
                    'event_timestamp': eq_time,
                    'status': status,
                    'temperature_c': round(temperature, 2),
                    'pressure_torr': round(pressure, 3),
                    'rf_power_w': round(np.random.normal(1500, 100), 1) if eq['equipment_type'] in ['ETCH', 'CVD'] else None,
                    'ingestion_timestamp': eq_time + timedelta(seconds=np.random.randint(1, 300))  # Some latency
                })
                
                eq_time += timedelta(minutes=cycle_duration)
        
        df = pd.DataFrame(all_logs)
        output_path = self.output_dir / 'raw' / 'equipment_logs.csv'
        output_path.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(output_path, index=False)
        print(f"✓ Generated {len(df):,} equipment log records → {output_path}")
        return df
    
    def generate_wafer_batches(self):
        """Generate wafer batch data"""
        print("Generating wafer batches...")
        
        batches = []
        batch_id = 1
        current_date = self.start_date
        end_date = self.start_date + timedelta(days=self.days)
        
        while current_date < end_date:
            for _ in range(self.BATCHES_PER_DAY):
                # Select equipment for this batch (one per process step)
                batch_equipment = {}
                for step in self.PROCESS_STEPS:
                    available_eq = self.equipment[self.equipment['equipment_type'] == step['equipment_type']]
                    batch_equipment[step['step_id']] = available_eq.sample(1).iloc[0]['equipment_id']
                
                batch_start = current_date + timedelta(hours=np.random.randint(0, 24))
                total_duration = sum([s['duration_min'] for s in self.PROCESS_STEPS])
                batch_end = batch_start + timedelta(minutes=total_duration) + timedelta(minutes=np.random.randint(-20, 60))
                
                batches.append({
                    'batch_id': f"B{batch_id:06d}",
                    'lot_number': f"LOT_{current_date.year}_{batch_id:04d}",
                    'recipe': np.random.choice(['CMOS_28nm_v3', 'FinFET_14nm_v2', 'GAA_7nm_v1']),
                    'start_time': batch_start,
                    'end_time': batch_end,
                    'equipment_sequence': ','.join([batch_equipment[s['step_id']] for s in self.PROCESS_STEPS]),
                    'wafer_count': self.WAFERS_PER_BATCH
                })
                
                batch_id += 1
            
            current_date += timedelta(days=1)
        
        df = pd.DataFrame(batches)
        output_path = self.output_dir / 'raw' / 'wafer_batches.csv'
        df.to_csv(output_path, index=False)
        print(f"✓ Generated {len(df):,} wafer batches → {output_path}")
        return df
    
    def generate_test_results(self, batches_df):
        """Generate wafer test results"""
        print("Generating test results...")
        
        test_results = []
        
        for _, batch in batches_df.iterrows():
            # Batch-level yield factor (some batches inherently better)
            batch_yield_factor = np.random.normal(0.95, 0.05)
            batch_yield_factor = np.clip(batch_yield_factor, 0.70, 0.99)
            
            equipment_seq = batch['equipment_sequence'].split(',')
            
            for wafer_num in range(1, self.WAFERS_PER_BATCH + 1):
                wafer_id = f"{batch['batch_id']}_W{wafer_num:02d}"
                
                # Position effect (edge wafers have lower yield)
                position_effect = 1.0 if 5 <= wafer_num <= 20 else 0.95
                
                # Process each step
                current_time = batch['start_time']
                
                for step_idx, step in enumerate(self.PROCESS_STEPS):
                    step_start = current_time
                    step_duration = step['duration_min'] + np.random.randint(-5, 10)
                    step_end = step_start + timedelta(minutes=step_duration)
                    
                    # Step success probability
                    step_yield = batch_yield_factor * position_effect * np.random.uniform(0.98, 1.0)
                    pass_fail = 'PASS' if np.random.random() < step_yield else 'FAIL'
                    
                    # If failed, subsequent steps may not happen or will also fail
                    if pass_fail == 'FAIL' and step_idx < len(self.PROCESS_STEPS) - 1:
                        if np.random.random() < 0.7:  # 70% chance to stop processing
                            break
                    
                    defect_density = np.random.exponential(0.5) if pass_fail == 'FAIL' else np.random.exponential(0.1)
                    
                    test_results.append({
                        'wafer_id': wafer_id,
                        'batch_id': batch['batch_id'],
                        'process_step_id': step['step_id'],
                        'process_step_name': step['name'],
                        'equipment_id': equipment_seq[step_idx],
                        'start_time': step_start,
                        'end_time': step_end,
                        'pass_fail': pass_fail,
                        'defect_density': round(defect_density, 3),
                        'bin_code': np.random.choice(['BIN1', 'BIN2', 'BIN3', 'BINX']) if pass_fail == 'PASS' else 'FAIL',
                        'test_timestamp': step_end
                    })
                    
                    current_time = step_end
        
        df = pd.DataFrame(test_results)
        output_path = self.output_dir / 'raw' / 'test_results.csv'
        df.to_csv(output_path, index=False)
        print(f"✓ Generated {len(df):,} test records → {output_path}")
        return df
    
    def generate_maintenance_events(self, equipment_logs_df):
        """Generate equipment maintenance events"""
        print("Generating maintenance events...")
        
        maintenance_events = []
        
        for eq_id in self.equipment['equipment_id']:
            # Get equipment logs for this tool
            eq_logs = equipment_logs_df[equipment_logs_df['equipment_id'] == eq_id].sort_values('event_timestamp')
            
            if len(eq_logs) == 0:
                continue
            
            # Schedule preventive maintenance every 7-14 days
            current_time = eq_logs['event_timestamp'].min()
            end_time = eq_logs['event_timestamp'].max()
            
            while current_time < end_time:
                # Preventive maintenance
                pm_interval = np.random.randint(7, 14)
                current_time += timedelta(days=pm_interval)
                
                if current_time > end_time:
                    break
                
                maintenance_events.append({
                    'event_id': f"PM_{eq_id}_{current_time.strftime('%Y%m%d')}",
                    'equipment_id': eq_id,
                    'event_type': 'PREVENTIVE',
                    'event_timestamp': current_time,
                    'duration_hours': np.random.randint(2, 8),
                    'parts_replaced': np.random.choice(['Chamber cleaning', 'Filter replacement', 'Calibration', 'None']),
                    'technician_id': f"TECH{np.random.randint(1, 20):02d}"
                })
            
            # Add some corrective maintenance based on ALARM/DOWN events
            problem_logs = eq_logs[eq_logs['status'].isin(['ALARM', 'DOWN'])]
            for _, log in problem_logs.sample(min(len(problem_logs), 5)).iterrows():  # Sample up to 5 issues
                maintenance_events.append({
                    'event_id': f"CM_{eq_id}_{log['event_timestamp'].strftime('%Y%m%d%H%M')}",
                    'equipment_id': eq_id,
                    'event_type': 'CORRECTIVE',
                    'event_timestamp': log['event_timestamp'] + timedelta(hours=np.random.randint(1, 4)),
                    'duration_hours': np.random.randint(1, 24),
                    'parts_replaced': np.random.choice(['Pump replacement', 'Sensor calibration', 'Software update', 'Valve repair']),
                    'technician_id': f"TECH{np.random.randint(1, 20):02d}"
                })
        
        df = pd.DataFrame(maintenance_events)
        output_path = self.output_dir / 'raw' / 'maintenance_events.csv'
        df.to_csv(output_path, index=False)
        print(f"✓ Generated {len(df):,} maintenance events → {output_path}")
        return df
    
    def generate_all(self):
        """Generate all data files"""
        print("\n" + "="*60)
        print("Semiconductor Manufacturing Data Generation")
        print("="*60)
        print(f"Start Date: {self.start_date.date()}")
        print(f"Duration: {self.days} days")
        print(f"Output Directory: {self.output_dir}")
        print("="*60 + "\n")
        
        # Generate equipment master data
        eq_output = self.output_dir / 'raw' / 'equipment_master.csv'
        self.equipment.to_csv(eq_output, index=False)
        print(f"✓ Generated {len(self.equipment)} equipment records → {eq_output}")
        
        # Generate process steps
        ps_output = self.output_dir / 'raw' / 'process_steps.csv'
        pd.DataFrame(self.PROCESS_STEPS).to_csv(ps_output, index=False)
        print(f"✓ Generated {len(self.PROCESS_STEPS)} process steps → {ps_output}\n")
        
        # Generate time-series data
        equipment_logs = self.generate_equipment_logs()
        batches = self.generate_wafer_batches()
        tests = self.generate_test_results(batches)
        maintenance = self.generate_maintenance_events(equipment_logs)
        
        print("\n" + "="*60)
        print("✅ Data Generation Complete!")
        print("="*60)
        print(f"Total Records Generated: {len(equipment_logs) + len(batches) + len(tests) + len(maintenance):,}")
        print(f"Equipment Logs: {len(equipment_logs):,}")
        print(f"Wafer Batches: {len(batches):,}")
        print(f"Test Results: {len(tests):,}")
        print(f"Maintenance Events: {len(maintenance):,}")
        print("="*60 + "\n")


def main():
    parser = argparse.ArgumentParser(description='Generate semiconductor manufacturing data')
    parser.add_argument('--start-date', type=str, default='2024-01-01', 
                        help='Start date (YYYY-MM-DD)')
    parser.add_argument('--days', type=int, default=30, 
                        help='Number of days to simulate')
    parser.add_argument('--output-dir', type=str, default='data', 
                        help='Output directory for generated data')
    
    args = parser.parse_args()
    
    generator = SemiconductorDataGenerator(
        start_date=args.start_date,
        days=args.days,
        output_dir=args.output_dir
    )
    
    generator.generate_all()


if __name__ == '__main__':
    main()
