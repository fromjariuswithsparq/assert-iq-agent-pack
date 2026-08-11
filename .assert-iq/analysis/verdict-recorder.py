#!/usr/bin/env python3
"""
Verdict Recorder Library
Provides utilities for skills to record verdicts to the verdict sink.
"""

import json
import os
from pathlib import Path
from datetime import datetime
import uuid

class VerdictRecorder:
    def __init__(self, workspace_root="."):
        self.workspace_root = Path(workspace_root)
        self.verdicts_dir = self.workspace_root / ".assert-iq" / "verdicts"
        self.archive_dir = self.verdicts_dir / "archive"
        
    def record_verdict(self, verdict_data):
        """
        Record a verdict to the verdict sink.
        
        Args:
            verdict_data (dict): Verdict object with required fields
                - verdict_type: pr_risk_assessment, release_confidence, etc.
                - verdict_band: green, amber, red, ungraded
                - verdict_score: 0.0-1.0
                - layer_scores: {change, protection, trust, outcome}
                - layer_weights: {change, protection, trust, outcome}
                - maturity_tier: early, mid, higher
                - memory_version: SHA256 hash
                - issued_by: skill name
                - pr_id: (optional) PR number
                - release_id: (optional) release tag
                - assumptions: list of assumption strings
                - linked_escape: null or escape dict
        
        Returns:
            dict: {success: bool, verdict_id: str, message: str}
        """
        try:
            # Generate verdict ID if not provided
            if 'verdict_id' not in verdict_data:
                verdict_data['verdict_id'] = str(uuid.uuid4())
            
            # Add issued_at if not provided
            if 'issued_at' not in verdict_data:
                verdict_data['issued_at'] = datetime.utcnow().isoformat() + 'Z'
            
            # Create archive directory structure (YYYY/MM)
            now = datetime.utcnow()
            year_month_dir = self.archive_dir / f"{now.year}" / f"{now.month:02d}"
            year_month_dir.mkdir(parents=True, exist_ok=True)
            
            # Determine verdict file (verdicts-DD.jsonl)
            verdict_file = year_month_dir / f"verdicts-{now.day:02d}.jsonl"
            
            # Append verdict to JSONL file
            with open(verdict_file, 'a') as f:
                f.write(json.dumps(verdict_data) + '\n')
            
            # Update index.json
            self._update_index(verdict_data)
            
            # Append to VERDICTS.md audit trail
            self._append_audit_trail(verdict_data)
            
            return {
                'success': True,
                'verdict_id': verdict_data['verdict_id'],
                'message': f"Verdict recorded: {verdict_file}"
            }
        except Exception as e:
            return {
                'success': False,
                'verdict_id': verdict_data.get('verdict_id'),
                'message': f"Error recording verdict: {str(e)}"
            }
    
    def _update_index(self, verdict_data):
        """Update verdict index."""
        index_file = self.verdicts_dir / "index.json"
        
        if index_file.exists():
            with open(index_file, 'r') as f:
                index = json.load(f)
        else:
            index = {
                'schema_version': '1.0',
                'verdicts_recorded': 0,
                'verdicts_by_band': {'green': 0, 'amber': 0, 'red': 0, 'ungraded': 0},
                'verdicts_by_type': {'pr_risk_assessment': 0, 'release_confidence': 0, 'other': 0},
                'verdicts_with_escapes': 0,
                'last_updated': None,
                'archive_paths': []
            }
        
        # Update counters
        index['verdicts_recorded'] += 1
        band = verdict_data.get('verdict_band', 'ungraded')
        if band in index['verdicts_by_band']:
            index['verdicts_by_band'][band] += 1
        
        v_type = verdict_data.get('verdict_type', 'other')
        if v_type in index['verdicts_by_type']:
            index['verdicts_by_type'][v_type] += 1
        
        if verdict_data.get('linked_escape'):
            index['verdicts_with_escapes'] += 1
        
        index['last_updated'] = datetime.utcnow().isoformat() + 'Z'
        
        # Write back
        with open(index_file, 'w') as f:
            json.dump(index, f, indent=2)
    
    def _append_audit_trail(self, verdict_data):
        """Append one-liner to audit trail."""
        trail_file = self.verdicts_dir / "VERDICTS.md"
        
        now = datetime.utcnow()
        timestamp = now.strftime("%Y-%m-%d %H:%M:%S UTC")
        verdict_id = verdict_data.get('verdict_id', 'unknown')
        v_type = verdict_data.get('verdict_type', 'other')
        band = verdict_data.get('verdict_band', 'ungraded')
        score = verdict_data.get('verdict_score', 0.0)
        pr_id = verdict_data.get('pr_id', 'N/A')
        layers = []
        for layer, info in verdict_data.get('layer_scores', {}).items():
            if isinstance(info, dict):
                layers.append(f"{layer}:{info.get('state', '?')}")
        layer_summary = ' '.join(layers) if layers else 'unknown'
        escape = verdict_data.get('linked_escape')
        escape_str = escape.get('defect_id', 'unknown') if escape else 'none'
        
        line = f"{timestamp} | {verdict_id} | {v_type} | {band} | {score} | {pr_id} | {layer_summary} | {escape_str}\n"
        
        with open(trail_file, 'a') as f:
            f.write(line)


if __name__ == "__main__":
    print("Verdict Recorder Library")
    print("Usage: Import VerdictRecorder in your skill code")
    print("Example:")
    print("  from verdict_recorder import VerdictRecorder")
    print("  recorder = VerdictRecorder()")
    print("  result = recorder.record_verdict(verdict_dict)")
