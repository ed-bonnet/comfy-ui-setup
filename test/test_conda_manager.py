import unittest
from unittest.mock import patch, MagicMock
import json
import logging
from dashboard.core.conda_manager import get_available_python_versions

# Configure logging to suppress error messages during testing
logging.getLogger('dashboard.core.conda_manager').setLevel(logging.CRITICAL)

class TestCondaManager(unittest.TestCase):
    @patch('dashboard.core.conda_manager.subprocess.run')
    def test_get_available_python_versions(self, mock_run):
        # Mock the conda search output
        mock_output = {
            "python": [
                {"version": "3.10.0", "name": "python"},
                {"version": "3.11.0", "name": "python"},
                {"version": "3.12.0", "name": "python"},
                {"version": "3.13.0", "name": "python"},
                {"version": "3.9.0", "name": "python"}  # Should be filtered out
            ]
        }
        mock_result = MagicMock()
        mock_result.stdout = json.dumps(mock_output)
        mock_result.returncode = 0
        mock_run.return_value = mock_result

        # Call the function
        versions = get_available_python_versions()

        # Verify the results
        self.assertEqual(len(versions), 3)
        self.assertEqual(versions[0], "3.13.0")
        self.assertEqual(versions[1], "3.12.0")
        self.assertEqual(versions[2], "3.11.0")
        self.assertNotIn("3.10.0", versions)
        self.assertNotIn("3.9.0", versions)

    @patch('dashboard.core.conda_manager.subprocess.run')
    def test_get_available_python_versions_empty(self, mock_run):
        # Mock empty output
        mock_result = MagicMock()
        mock_result.stdout = json.dumps({"python": []})
        mock_result.returncode = 0
        mock_run.return_value = mock_result

        # Call the function
        versions = get_available_python_versions()

        # Verify the results
        self.assertEqual(len(versions), 0)

    @patch('dashboard.core.conda_manager.subprocess.run')
    def test_get_available_python_versions_error(self, mock_run):
        # Mock error case
        mock_run.side_effect = Exception("Command failed")

        # Call the function
        versions = get_available_python_versions()

        # Verify the results
        self.assertEqual(len(versions), 0)

if __name__ == '__main__':
    unittest.main()
