package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"text/tabwriter"
	"time"

	gounits "github.com/docker/go-units"
	"github.com/google/go-github/v57/github"
)

type ArtifactFile struct {
	Name string `json:"name"`
	Size int64  `json:"size"`
}

type ArtifactRun struct {
	RunName    string         `json:"run_name"`
	Timestamp  time.Time      `json:"timestamp"`
	Script     string         `json:"script"`
	Runner     string         `json:"runner"`
	LocalPath  string         `json:"local_path"`
	ReleaseURL string         `json:"release_url,omitempty"`
	Files      []ArtifactFile `json:"files"`
}

type ArtifactManifest struct {
	Runs []ArtifactRun `json:"runs"`
}

type ReleaseMetadata struct {
	Script    string
	Runner    string
	StartTime time.Time
	EndTime   time.Time
	RunName   string
}

func manifestPath() (string, error) {
	configDir, err := os.UserConfigDir()
	if err != nil {
		return "", fmt.Errorf("failed to get config dir: %w", err)
	}
	dir := filepath.Join(configDir, "actions-batch")
	if err := os.MkdirAll(dir, 0755); err != nil {
		return "", fmt.Errorf("failed to create config dir: %w", err)
	}
	return filepath.Join(dir, "artifacts.json"), nil
}

func loadManifest() (*ArtifactManifest, error) {
	p, err := manifestPath()
	if err != nil {
		return nil, err
	}

	data, err := os.ReadFile(p)
	if err != nil {
		if os.IsNotExist(err) {
			return &ArtifactManifest{}, nil
		}
		return nil, fmt.Errorf("failed to read manifest: %w", err)
	}

	var m ArtifactManifest
	if err := json.Unmarshal(data, &m); err != nil {
		return nil, fmt.Errorf("failed to parse manifest: %w", err)
	}
	return &m, nil
}

func appendManifestEntry(entry ArtifactRun) error {
	m, err := loadManifest()
	if err != nil {
		return err
	}

	m.Runs = append(m.Runs, entry)

	data, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal manifest: %w", err)
	}

	p, err := manifestPath()
	if err != nil {
		return err
	}

	tmpFile := p + ".tmp"
	if err := os.WriteFile(tmpFile, data, 0644); err != nil {
		return fmt.Errorf("failed to write manifest: %w", err)
	}

	return os.Rename(tmpFile, p)
}

func persistToRelease(ctx context.Context, client *github.Client, artifactsRepo, runName, artifactsDir string, meta ReleaseMetadata) (string, error) {
	parts := strings.SplitN(artifactsRepo, "/", 2)
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return "", fmt.Errorf("--artifacts-repo must be in format owner/repo, got: %s", artifactsRepo)
	}
	repoOwner, repoName := parts[0], parts[1]

	if _, resp, err := client.Repositories.Get(ctx, repoOwner, repoName); err != nil {
		if resp != nil && resp.StatusCode == 404 {
			return "", fmt.Errorf("artifacts repo %s does not exist — please create it first", artifactsRepo)
		}
		return "", fmt.Errorf("failed to check artifacts repo: %w", err)
	}

	tag := fmt.Sprintf("run-%s-%s", runName, time.Now().Format("20060102-150405"))

	body := fmt.Sprintf("## Run: %s\n\n- **Script:** %s\n- **Runner:** %s\n- **Started:** %s\n- **Ended:** %s\n",
		meta.RunName, meta.Script, meta.Runner,
		meta.StartTime.Format(time.RFC3339),
		meta.EndTime.Format(time.RFC3339))

	release, _, err := client.Repositories.CreateRelease(ctx, repoOwner, repoName, &github.RepositoryRelease{
		TagName:    github.String(tag),
		Name:       github.String(fmt.Sprintf("Run: %s", runName)),
		Body:       github.String(body),
		MakeLatest: github.String("false"),
	})
	if err != nil {
		return "", fmt.Errorf("failed to create release: %w", err)
	}

	entries, err := os.ReadDir(artifactsDir)
	if err != nil {
		return release.GetHTMLURL(), fmt.Errorf("failed to read artifacts dir: %w", err)
	}

	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		filePath := filepath.Join(artifactsDir, entry.Name())
		f, err := os.Open(filePath)
		if err != nil {
			fmt.Printf("Warning: failed to open %s for upload: %s\n", entry.Name(), err)
			continue
		}

		_, _, err = client.Repositories.UploadReleaseAsset(ctx, repoOwner, repoName, release.GetID(), &github.UploadOptions{
			Name: entry.Name(),
		}, f)
		f.Close()

		if err != nil {
			fmt.Printf("Warning: failed to upload %s: %s\n", entry.Name(), err)
			continue
		}
	}

	return release.GetHTMLURL(), nil
}

func listArtifacts() error {
	m, err := loadManifest()
	if err != nil {
		return err
	}

	if len(m.Runs) == 0 {
		fmt.Println("No artifacts tracked yet.")
		return nil
	}

	t := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintf(t, "RUN NAME\tDATE\tFILES\tSIZE\tLOCAL PATH\tRELEASE URL\n")

	for _, run := range m.Runs {
		var totalSize int64
		for _, f := range run.Files {
			totalSize += f.Size
		}

		releaseURL := run.ReleaseURL
		if releaseURL == "" {
			releaseURL = "-"
		}

		fmt.Fprintf(t, "%s\t%s\t%d\t%s\t%s\t%s\n",
			run.RunName,
			run.Timestamp.Format("2006-01-02 15:04"),
			len(run.Files),
			gounits.HumanSize(float64(totalSize)),
			run.LocalPath,
			releaseURL,
		)
	}

	fmt.Fprintf(t, "\n")
	t.Flush()
	return nil
}
