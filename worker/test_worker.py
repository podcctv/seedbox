import worker
from unittest.mock import patch
import requests


def test_next_job_sends_token():
    with patch("requests.post") as post:
        post.return_value.status_code = 200
        post.return_value.json.return_value = {"id": 1, "path": "/tmp/video.mp4"}
        worker.next_job()
        assert post.call_args.kwargs["headers"]["X-Auth"] == worker.API_TOKEN


def test_report_done_uses_file(tmp_path):
    dummy = tmp_path / "demo.jpg"
    dummy.write_text("demo")
    with patch("requests.post") as post:
        post.return_value.status_code = 200
        worker.report_done(1, str(dummy))
        assert post.call_args.args[0].endswith("/jobs/1/done")
        assert "files" in post.call_args.kwargs


def test_run_handles_connection_errors():
    with patch("worker.next_job", side_effect=requests.ConnectionError), patch(
        "time.sleep", side_effect=KeyboardInterrupt
    ) as sleep:
        try:
            worker.run()
        except KeyboardInterrupt:
            pass
        sleep.assert_called()
