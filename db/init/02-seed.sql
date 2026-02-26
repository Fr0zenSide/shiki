INSERT INTO projects (slug, name, description, repo_url) VALUES
    ('wabisabi', 'WabiSabi', 'iOS mindfulness habit app — wabi-sabi philosophy', 'https://github.com/example/app'),
    ('ail',      'AIL',      'AI Link — distributed computing device from ESP32 controllers', NULL)
ON CONFLICT (slug) DO NOTHING;
