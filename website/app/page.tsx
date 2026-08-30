import sourceHtml from '../index.html?raw';

const bodyMatch = sourceHtml.match(/<body[^>]*>([\s\S]*?)<\/body>/i);
const siteMarkup = (bodyMatch?.[1] ?? sourceHtml).replace(/<script[\s\S]*?<\/script>/gi, '');

export default function HomePage() {
  return <div dangerouslySetInnerHTML={{ __html: siteMarkup }} />;
}
